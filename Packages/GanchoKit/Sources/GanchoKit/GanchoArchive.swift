import CryptoKit
import Foundation
import GRDB

/// The portable exit/recovery format: a `.ganchoarchive` directory with a
/// checksummed manifest, the clip rows, and the binary blobs. Never uploaded
/// anywhere by Gancho; it also powers importers, support, and future
/// non-Apple clients. Always available — Free included (no lock-in).
public enum GanchoArchive {
    public static let currentVersion = 1

    public struct Options: Sendable, Equatable {
        /// Drop sensitive clips entirely from the archive.
        public var excludeSensitive: Bool
        /// Metadata only: no content text, no blobs (pins/structure rescue).
        public var metadataOnly: Bool

        public init(excludeSensitive: Bool = false, metadataOnly: Bool = false) {
            self.excludeSensitive = excludeSensitive
            self.metadataOnly = metadataOnly
        }
    }

    public struct Manifest: Sendable, Equatable, Codable {
        public var version: Int
        public var exportedAt: Date
        public var clipCount: Int
        /// SHA-256 per archive file (clips.json + each blob).
        public var checksums: [String: String]
    }

    public struct RestoreSummary: Sendable, Equatable {
        public var inserted: Int
        public var skippedDuplicates: Int
    }

    public enum ArchiveError: Error, Equatable {
        case unsupportedVersion(Int)
        case corruptArchive(String)
        case checksumMismatch(String)
    }

    // MARK: - Export

    @discardableResult
    public static func export(
        from store: GRDBClipboardStore, to directory: URL, options: Options = Options()
    ) async throws -> Manifest {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var rows = try await store.writer.read { db in
            try ClipRow.order(Column("createdAt").asc).fetchAll(db)
        }
        if options.excludeSensitive {
            rows.removeAll(where: \.isSensitive)
        }
        if options.metadataOnly {
            for index in rows.indices {
                rows[index].contentText = nil
                rows[index].contentBlobHash = nil
            }
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let clipsData = try encoder.encode(rows)
        try clipsData.write(to: directory.appendingPathComponent("clips.json"), options: .atomic)

        var checksums = ["clips.json": sha256(clipsData)]

        if !options.metadataOnly {
            let blobDir = directory.appendingPathComponent("blobs", isDirectory: true)
            try FileManager.default.createDirectory(
                at: blobDir, withIntermediateDirectories: true)
            for hash in Set(rows.compactMap(\.contentBlobHash)) {
                guard let data = try store.blobsForMaintenance.read(hash: hash) else { continue }
                try data.write(to: blobDir.appendingPathComponent(hash), options: .atomic)
                checksums["blobs/\(hash)"] = sha256(data)
            }
        }

        let manifest = Manifest(
            version: currentVersion, exportedAt: .now, clipCount: rows.count,
            checksums: checksums)
        let manifestEncoder = JSONEncoder()
        manifestEncoder.dateEncodingStrategy = .iso8601
        manifestEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try manifestEncoder.encode(manifest)
            .write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
        return manifest
    }

    // MARK: - Restore (merge with dedupe; transactional rollback)

    @discardableResult
    public static func restore(
        from directory: URL, into store: GRDBClipboardStore
    ) async throws -> RestoreSummary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard
            let manifestData = try? Data(
                contentsOf: directory.appendingPathComponent("manifest.json")),
            let manifest = try? decoder.decode(Manifest.self, from: manifestData)
        else { throw ArchiveError.corruptArchive("manifest.json missing or unreadable") }

        guard manifest.version <= currentVersion else {
            throw ArchiveError.unsupportedVersion(manifest.version)
        }

        // Verify EVERY checksum before touching the store.
        guard
            let clipsData = try? Data(contentsOf: directory.appendingPathComponent("clips.json"))
        else { throw ArchiveError.corruptArchive("clips.json missing") }
        guard sha256(clipsData) == manifest.checksums["clips.json"] else {
            throw ArchiveError.checksumMismatch("clips.json")
        }
        for (path, expected) in manifest.checksums where path.hasPrefix("blobs/") {
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(path)),
                sha256(data) == expected
            else { throw ArchiveError.checksumMismatch(path) }
        }

        let rows: [ClipRow]
        do {
            rows = try decoder.decode([ClipRow].self, from: clipsData)
        } catch {
            throw ArchiveError.corruptArchive("clips.json does not decode")
        }

        // Blobs first (content-addressed = idempotent), then rows in ONE
        // transaction: any failure rolls the database back untouched.
        for (path, _) in manifest.checksums where path.hasPrefix("blobs/") {
            let data = try Data(contentsOf: directory.appendingPathComponent(path))
            try store.blobsForMaintenance.write(data)
        }

        return try await store.writer.write { db in
            var summary = RestoreSummary(inserted: 0, skippedDuplicates: 0)
            for row in rows {
                let exists =
                    try ClipRow
                    .filter(Column("contentHash") == row.contentHash)
                    .filter(Column("sourceDeviceName") == row.sourceDeviceName)
                    .fetchCount(db) > 0
                if exists {
                    summary.skippedDuplicates += 1
                } else {
                    var fresh = row
                    // Avoid id collisions with self-restores.
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

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
