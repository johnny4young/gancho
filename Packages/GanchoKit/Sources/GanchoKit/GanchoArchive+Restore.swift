import CryptoKit
import Foundation
import GRDB

extension GanchoArchive {
    /// Hostile-input ceilings for untrusted archives — anti-abuse sanity
    /// bounds only, NOT product expectations. Capture is uncapped, so every
    /// ceiling must sit far above anything a real store produces; the point
    /// is to reject absurd inputs, never a legitimate backup. Internal so
    /// tests can exercise every boundary with tiny fixtures without
    /// allocating production-sized files.
    struct RestoreLimits: Sendable, Equatable {
        var manifestBytes = 32 << 20
        var clipsBytes = 1 << 30
        var rowCount = 1_000_000
        var blobCount = 100_000
        var blobBytes = 1 << 30
        var totalBlobBytes: Int64 = 100 << 30

        static let production = RestoreLimits()
    }

    @discardableResult
    static func restore(
        from directory: URL, into store: GRDBClipboardStore, limits: RestoreLimits
    ) async throws -> RestoreSummary {
        let archive = try validatedArchive(from: directory, limits: limits)
        return try await apply(archive, to: store)
    }

    private struct ValidatedArchive {
        let root: ArchiveRoot
        let rows: [ClipRow]
        let blobs: [ArchiveBlob]
        let limits: RestoreLimits
    }

    private struct ArchiveRoot {
        let url: URL
        let canonicalURL: URL
    }

    private struct ArchiveFile {
        let relativePath: String
        let url: URL
        let size: Int64
        let maximumBytes: Int
        let unreadableMessage: String
    }

    private struct ArchiveBlob {
        let hash: String
        let path: String
    }

    private struct DeclaredFiles {
        let clipsChecksum: String
        let blobs: [ArchiveBlob]
    }

    private static func validatedArchive(
        from directory: URL, limits: RestoreLimits
    ) throws -> ValidatedArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let root = try archiveRoot(directory)
        let manifest = try decodeManifest(in: root, with: decoder, limits: limits)
        let declared = try declaredFiles(in: manifest, limits: limits)
        let rows = try validatedRows(
            in: root, manifest: manifest, declared: declared,
            decoder: decoder, limits: limits)
        let declaredBlobs = try validatedBlobs(in: root, declared: declared, limits: limits)
        let blobs = try referencedBlobs(in: rows, among: declaredBlobs)
        return ValidatedArchive(root: root, rows: rows, blobs: blobs, limits: limits)
    }

    private static func decodeManifest(
        in root: ArchiveRoot, with decoder: JSONDecoder, limits: RestoreLimits
    ) throws -> Manifest {
        let file = try regularFile(
            "manifest.json", in: root, maximumBytes: limits.manifestBytes,
            unreadableMessage: "manifest.json missing or unreadable")
        guard let data = try? read(file),
            let manifest = try? decoder.decode(Manifest.self, from: data)
        else { throw ArchiveError.corruptArchive("manifest.json missing or unreadable") }

        guard manifest.version <= currentVersion else {
            throw ArchiveError.unsupportedVersion(manifest.version)
        }
        guard manifest.version > 0 else {
            throw ArchiveError.corruptArchive("manifest.json has an invalid version")
        }
        guard (0...limits.rowCount).contains(manifest.clipCount) else {
            throw ArchiveError.corruptArchive("manifest.json exceeds the clip-count limit")
        }
        return manifest
    }

    private static func validatedRows(
        in root: ArchiveRoot, manifest: Manifest, declared: DeclaredFiles,
        decoder: JSONDecoder, limits: RestoreLimits
    ) throws -> [ClipRow] {
        let file = try regularFile(
            "clips.json", in: root, maximumBytes: limits.clipsBytes,
            unreadableMessage: "clips.json missing or unreadable")
        // One read: hash and decode the SAME bytes, so a file swapped between
        // the checksum and the decode can never smuggle unverified rows in.
        let data = try read(file)
        guard sha256(data) == declared.clipsChecksum else {
            throw ArchiveError.checksumMismatch("clips.json")
        }
        let rows: [ClipRow]
        do {
            rows = try decoder.decode([ClipRow].self, from: data)
        } catch {
            throw ArchiveError.corruptArchive("clips.json does not decode")
        }
        guard rows.count == manifest.clipCount else {
            throw ArchiveError.corruptArchive("manifest clip count does not match clips.json")
        }
        return rows
    }

    private static func validatedBlobs(
        in root: ArchiveRoot, declared: DeclaredFiles, limits: RestoreLimits
    ) throws -> [ArchiveBlob] {
        if !declared.blobs.isEmpty { try validateBlobDirectory(in: root) }
        var result: [ArchiveBlob] = []
        result.reserveCapacity(declared.blobs.count)
        var totalBytes: Int64 = 0
        for blob in declared.blobs.sorted(by: { $0.hash < $1.hash }) {
            try Task.checkCancellation()
            // Stat-based bounds only (regular file, containment, per-blob and
            // aggregate size). Content hashes are verified once, at write
            // time, on the exact bytes that enter the store.
            let file = try regularFile(
                blob.path, in: root, maximumBytes: limits.blobBytes,
                unreadableMessage: "a declared blob is missing or unreadable")
            let (newTotal, overflow) = totalBytes.addingReportingOverflow(file.size)
            guard !overflow, newTotal <= limits.totalBlobBytes else {
                throw ArchiveError.corruptArchive("archive exceeds the total blob-size limit")
            }
            totalBytes = newTotal
            result.append(blob)
        }
        return result
    }

    /// The shipped version-1 exporter silently skipped store-missing blobs
    /// while keeping the rows that reference them, so a referenced hash with
    /// no declaration is a legal legacy archive — the row restores without
    /// its payload, exactly as the original restore behaved. The reverse
    /// mismatch (a declared blob no row references) is validated above but
    /// skipped here so junk never enters the store.
    private static func referencedBlobs(
        in rows: [ClipRow], among blobs: [ArchiveBlob]
    ) throws -> [ArchiveBlob] {
        let referenced = try referencedBlobHashes(in: rows)
        return blobs.filter { referenced.contains($0.hash) }
    }

    private static func apply(
        _ archive: ValidatedArchive, to store: GRDBClipboardStore
    ) async throws -> RestoreSummary {
        // Blobs first (content-addressed = idempotent), then rows in ONE
        // transaction. A crash or failure can leave an orphaned blob file but
        // never a dangling row — and restore deliberately does NOT clean
        // orphans up: blob-creation ownership can't be decided atomically with
        // the database, so an eager delete can race a concurrent capture that
        // just adopted the same hash and destroy a live clip's payload. An
        // orphan is the harmless outcome — a content-addressed file no row
        // references, re-adopted verbatim by any future capture of the same
        // content.
        try writeBlobs(archive, to: store)
        return try await restoreRows(archive.rows, into: store)
    }

    private static func writeBlobs(
        _ archive: ValidatedArchive, to store: GRDBClipboardStore
    ) throws {
        for blob in archive.blobs {
            try Task.checkCancellation()
            // Hash the exact bytes being written, immediately before writing
            // them: the in-memory Data can't change between this guard and
            // the store write, so this one hash is the whole guarantee — a
            // file swapped after validation never enters the live store.
            let current = try regularFile(
                blob.path, in: archive.root, maximumBytes: archive.limits.blobBytes,
                unreadableMessage: "a declared blob is missing or unreadable")
            let data = try read(current)
            guard sha256(data) == blob.hash else {
                throw ArchiveError.checksumMismatch(blob.path)
            }
            _ = try store.blobsForMaintenance.write(data)
        }
    }

    private static func restoreRows(
        _ rows: [ClipRow], into store: GRDBClipboardStore
    ) async throws -> RestoreSummary {
        try await store.writer.write { db in
            var summary = RestoreSummary(inserted: 0, skippedDuplicates: 0)
            for row in rows {
                try Task.checkCancellation()
                let exists =
                    try ClipRow
                    .filter(Column("contentHash") == row.contentHash)
                    .filter(Column("sourceDeviceName") == row.sourceDeviceName)
                    .fetchCount(db) > 0
                if exists {
                    summary.skippedDuplicates += 1
                } else {
                    var fresh = row
                    if try ClipRow.filter(key: row.id).fetchCount(db) > 0 {
                        fresh.id = UUID().uuidString
                    }
                    try fresh.insert(db)
                    summary.inserted += 1
                }
            }
            return summary
        }
    }

    // MARK: - File validation

    private static func archiveRoot(_ directory: URL) throws -> ArchiveRoot {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        } catch {
            throw ArchiveError.corruptArchive("archive directory is missing or unreadable")
        }
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw ArchiveError.corruptArchive("archive must be a regular directory")
        }
        return ArchiveRoot(
            url: directory.standardizedFileURL,
            canonicalURL: directory.standardizedFileURL.resolvingSymlinksInPath())
    }

    private static func declaredFiles(
        in manifest: Manifest, limits: RestoreLimits
    ) throws -> DeclaredFiles {
        guard let clipsChecksum = manifest.checksums["clips.json"],
            isLowercaseSHA256(clipsChecksum)
        else {
            throw ArchiveError.corruptArchive("manifest has no valid clips.json checksum")
        }

        var blobs: [ArchiveBlob] = []
        blobs.reserveCapacity(max(0, manifest.checksums.count - 1))
        for (path, checksum) in manifest.checksums where path != "clips.json" {
            guard path.hasPrefix("blobs/"), path.utf8.count == 70 else {
                throw ArchiveError.corruptArchive("manifest contains an invalid checksum path")
            }
            let hash = String(path.dropFirst("blobs/".count))
            guard isLowercaseSHA256(hash), checksum == hash else {
                throw ArchiveError.corruptArchive("manifest contains an invalid blob checksum")
            }
            blobs.append(ArchiveBlob(hash: hash, path: path))
        }
        guard blobs.count <= limits.blobCount else {
            throw ArchiveError.corruptArchive("manifest exceeds the blob-count limit")
        }
        return DeclaredFiles(clipsChecksum: clipsChecksum, blobs: blobs)
    }

    private static func validateBlobDirectory(in root: ArchiveRoot) throws {
        let directory = root.url.appendingPathComponent("blobs", isDirectory: true)
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        } catch {
            throw ArchiveError.corruptArchive("blobs directory is missing or unreadable")
        }
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
            isDescendant(directory.resolvingSymlinksInPath(), of: root.canonicalURL)
        else {
            throw ArchiveError.corruptArchive("blobs must be a regular archive directory")
        }
    }

    private static func regularFile(
        _ relativePath: String, in root: ArchiveRoot, maximumBytes: Int,
        unreadableMessage: String
    ) throws -> ArchiveFile {
        let url = root.url.appendingPathComponent(relativePath)
        guard isDescendant(url.resolvingSymlinksInPath(), of: root.canonicalURL) else {
            throw ArchiveError.corruptArchive("declared file escapes the archive directory")
        }

        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw ArchiveError.corruptArchive(unreadableMessage)
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
            let size = (attributes[.size] as? NSNumber)?.int64Value,
            size >= 0
        else {
            throw ArchiveError.corruptArchive("declared archive files must be regular files")
        }
        guard size <= Int64(maximumBytes) else {
            throw ArchiveError.corruptArchive("\(relativePath) exceeds its size limit")
        }
        return ArchiveFile(
            relativePath: relativePath, url: url, size: size,
            maximumBytes: maximumBytes, unreadableMessage: unreadableMessage)
    }

    private static func read(_ file: ArchiveFile) throws -> Data {
        do {
            let handle = try FileHandle(forReadingFrom: file.url)
            defer { try? handle.close() }
            var result = Data()
            result.reserveCapacity(Int(file.size))
            while let chunk = try handle.read(upToCount: 64 << 10), !chunk.isEmpty {
                guard result.count <= file.maximumBytes - chunk.count else {
                    throw ArchiveError.corruptArchive(
                        "\(file.relativePath) exceeds its size limit")
                }
                result.append(chunk)
            }
            return result
        } catch let error as ArchiveError {
            throw error
        } catch {
            throw ArchiveError.corruptArchive(file.unreadableMessage)
        }
    }

    private static func referencedBlobHashes(in rows: [ClipRow]) throws -> Set<String> {
        var references: Set<String> = []
        for hash in rows.compactMap(\.contentBlobHash) {
            guard isLowercaseSHA256(hash) else {
                throw ArchiveError.corruptArchive(
                    "clips.json contains an invalid blob reference")
            }
            references.insert(hash)
        }
        return references
    }

    private static func isDescendant(_ candidate: URL, of directory: URL) -> Bool {
        let root = directory.standardizedFileURL.path
        let path = candidate.standardizedFileURL.path
        return path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        let bytes = value.utf8
        return bytes.count == 64
            && bytes.allSatisfy { byte in
                (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
                    || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
            }
    }
}
