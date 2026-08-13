import CryptoKit
import Foundation
import GRDB

extension GanchoArchive {
    /// Explicit resource ceilings for untrusted archive input. Internal so
    /// tests can exercise every boundary with tiny fixtures without allocating
    /// production-sized files.
    struct RestoreLimits: Sendable, Equatable {
        var manifestBytes = 1 << 20
        var clipsBytes = 256 << 20
        var rowCount = 100_000
        var blobCount = 100_000
        var blobBytes = 20 << 20
        var totalBlobBytes: Int64 = 1 << 30

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

    private struct DeclaredBlob {
        let hash: String
        let path: String
    }

    private struct ArchiveBlob {
        let hash: String
        let path: String
    }

    private struct DeclaredFiles {
        let clipsChecksum: String
        let blobs: [DeclaredBlob]
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
        let blobs = try validatedBlobs(in: root, declared: declared, limits: limits)
        try validateRelationships(rows: rows, blobs: blobs)
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
        guard try streamedSHA256(file) == declared.clipsChecksum else {
            throw ArchiveError.checksumMismatch("clips.json")
        }
        let rows: [ClipRow]
        do {
            rows = try decoder.decode([ClipRow].self, from: read(file))
        } catch let error as ArchiveError {
            throw error
        } catch {
            throw ArchiveError.corruptArchive("clips.json does not decode")
        }
        guard rows.count == manifest.clipCount else {
            throw ArchiveError.corruptArchive("manifest clip count does not match clips.json")
        }
        guard rows.count <= limits.rowCount else {
            throw ArchiveError.corruptArchive("clips.json exceeds the row-count limit")
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
            let file = try regularFile(
                blob.path, in: root, maximumBytes: limits.blobBytes,
                unreadableMessage: "a declared blob is missing or unreadable")
            let (newTotal, overflow) = totalBytes.addingReportingOverflow(file.size)
            guard !overflow, newTotal <= limits.totalBlobBytes else {
                throw ArchiveError.corruptArchive("archive exceeds the total blob-size limit")
            }
            guard try streamedSHA256(file) == blob.hash else {
                throw ArchiveError.checksumMismatch(blob.path)
            }
            totalBytes = newTotal
            result.append(ArchiveBlob(hash: blob.hash, path: blob.path))
        }
        return result
    }

    private static func validateRelationships(
        rows: [ClipRow], blobs: [ArchiveBlob]
    ) throws {
        let referenced = try referencedBlobHashes(in: rows)
        guard referenced == Set(blobs.map(\.hash)) else {
            throw ArchiveError.corruptArchive(
                "blob declarations do not exactly match clips.json references")
        }
    }

    private static func apply(
        _ archive: ValidatedArchive, to store: GRDBClipboardStore
    ) async throws -> RestoreSummary {
        // Blobs first (content-addressed = idempotent), then rows in ONE
        // transaction. A crash can leave an orphan but never a dangling row;
        // ordinary failures remove only files this restore created, after a DB
        // reference check, and never delete a pre-existing live blob.
        var createdBlobs: Set<String> = []
        do {
            try writeBlobs(archive, to: store, created: &createdBlobs)
            let summary = try await restoreRows(archive.rows, into: store)
            await removeUnreferenced(createdBlobs, from: store)
            return summary
        } catch {
            await removeUnreferenced(createdBlobs, from: store)
            throw error
        }
    }

    private static func writeBlobs(
        _ archive: ValidatedArchive, to store: GRDBClipboardStore,
        created: inout Set<String>
    ) throws {
        for blob in archive.blobs {
            try Task.checkCancellation()
            // Re-open and re-hash immediately before the write. The first pass
            // proved the whole archive before mutation; this prevents a file
            // changed between phases from entering the live store.
            let current = try regularFile(
                blob.path, in: archive.root, maximumBytes: archive.limits.blobBytes,
                unreadableMessage: "a declared blob is missing or unreadable")
            let data = try read(current)
            guard sha256(data) == blob.hash else {
                throw ArchiveError.checksumMismatch(blob.path)
            }
            let existed = store.blobsForMaintenance.contains(hash: blob.hash)
            guard try store.blobsForMaintenance.write(data) == blob.hash else {
                throw ArchiveError.checksumMismatch(blob.path)
            }
            if !existed { created.insert(blob.hash) }
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

        var blobs: [DeclaredBlob] = []
        blobs.reserveCapacity(max(0, manifest.checksums.count - 1))
        for (path, checksum) in manifest.checksums where path != "clips.json" {
            guard path.hasPrefix("blobs/"), path.utf8.count == 70 else {
                throw ArchiveError.corruptArchive("manifest contains an invalid checksum path")
            }
            let hash = String(path.dropFirst("blobs/".count))
            guard isLowercaseSHA256(hash), checksum == hash else {
                throw ArchiveError.corruptArchive("manifest contains an invalid blob checksum")
            }
            blobs.append(DeclaredBlob(hash: hash, path: path))
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

    private static func streamedSHA256(_ file: ArchiveFile) throws -> String {
        do {
            let handle = try FileHandle(forReadingFrom: file.url)
            defer { try? handle.close() }
            var hasher = SHA256()
            var count = 0
            while let chunk = try handle.read(upToCount: 64 << 10), !chunk.isEmpty {
                guard count <= file.maximumBytes - chunk.count else {
                    throw ArchiveError.corruptArchive(
                        "\(file.relativePath) exceeds its size limit")
                }
                count += chunk.count
                hasher.update(data: chunk)
            }
            return hex(hasher.finalize())
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

    private static func removeUnreferenced(
        _ candidates: Set<String>, from store: GRDBClipboardStore
    ) async {
        guard !candidates.isEmpty else { return }
        let hashes = Array(candidates)
        let referenced: Set<String>
        do {
            referenced = try await store.writer.read { db in
                var found: Set<String> = []
                for start in stride(from: 0, to: hashes.count, by: 500) {
                    let chunk = Array(hashes[start..<min(start + 500, hashes.count)])
                    let placeholders = Array(repeating: "?", count: chunk.count)
                        .joined(separator: ",")
                    found.formUnion(
                        try String.fetchAll(
                            db,
                            sql: "SELECT DISTINCT contentBlobHash FROM clip "
                                + "WHERE contentBlobHash IN (\(placeholders))",
                            arguments: StatementArguments(chunk)))
                }
                return found
            }
        } catch {
            // Fail safe: an orphan is reclaimable by maintenance; deleting a
            // blob without proving it is unreferenced could strand live data.
            return
        }
        for hash in candidates.subtracting(referenced) {
            store.blobsForMaintenance.delete(hash: hash)
        }
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
