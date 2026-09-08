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

        public init(excludeSensitive: Bool = true, metadataOnly: Bool = false) {
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

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        // Streamed row by row rather than fetched, filtered and encoded as one
        // array: an export used to hold the entire history in memory twice
        // over — every row WITH its content, and then the encoded JSON of all
        // of them — which is the whole database for anyone with a long one.
        //
        // The bytes are identical to encoding the array. With `.sortedKeys`
        // and no pretty-printing a JSON array is exactly `[`, its elements
        // joined by `,`, and `]`, and `ExportStreamingTests` pins that against
        // `encoder.encode(rows)` so the format and its checksum cannot drift.
        let clipsURL = directory.appendingPathComponent("clips.json")
        let staged = directory.appendingPathComponent(".clips.json.\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: staged.path, contents: nil) else {
            throw ArchiveError.corruptArchive("could not stage the export")
        }

        // Everything the stream touches lives INSIDE the read closure: it is
        // `@Sendable`, so state mutated across that boundary would not compile,
        // and keeping the handle and the hasher local is also what makes the
        // export a single pass with nothing held afterwards.
        let streamed: (count: Int, blobs: Set<String>, digest: String)
        do {
            streamed = try await streamRows(
                from: store, to: staged, options: options, encoder: encoder)
        } catch {
            try? FileManager.default.removeItem(at: staged)
            throw error
        }
        // Renamed only once it is whole, so a failed export leaves no
        // half-written clips.json where the old code wrote atomically.
        _ = try? FileManager.default.removeItem(at: clipsURL)
        try FileManager.default.moveItem(at: staged, to: clipsURL)

        let clipCount = streamed.count
        let referencedBlobs = streamed.blobs
        var checksums = ["clips.json": streamed.digest]

        if !options.metadataOnly {
            let blobDir = directory.appendingPathComponent("blobs", isDirectory: true)
            try FileManager.default.createDirectory(
                at: blobDir, withIntermediateDirectories: true)
            for hash in referencedBlobs {
                guard let data = try store.blobsForMaintenance.read(hash: hash) else {
                    throw ArchiveError.corruptArchive(
                        "source store is missing or has a corrupt referenced blob")
                }
                // One digest serves both the integrity guard and the manifest.
                let digest = sha256(data)
                guard digest == hash else {
                    throw ArchiveError.corruptArchive(
                        "source store is missing or has a corrupt referenced blob")
                }
                try data.write(to: blobDir.appendingPathComponent(hash), options: .atomic)
                checksums["blobs/\(hash)"] = digest
            }
        }

        let manifest = Manifest(
            version: currentVersion, exportedAt: .now, clipCount: clipCount,
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
        try await restore(from: directory, into: store, limits: .production)
    }

    static func sha256(_ data: Data) -> String {
        hex(SHA256.hash(data: data))
    }

    static func hex(_ digest: some Sequence<UInt8>) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Writes every exported row to `destination` as one JSON array, hashing
    /// the bytes as they go.
    ///
    /// Split out so `export` stays inside the body-length limit — and because
    /// the streaming pass is the part with an invariant worth naming: the bytes
    /// must match what encoding the whole array would have produced, since the
    /// digest of this file is a restore contract.
    private static func streamRows(
        from store: GRDBClipboardStore, to destination: URL, options: Options,
        encoder: JSONEncoder
    ) async throws -> (count: Int, blobs: Set<String>, digest: String) {
        try await store.writer.read { db in
            let handle = try FileHandle(forWritingTo: destination)
            defer { try? handle.close() }
            var hasher = SHA256()
            var count = 0
            var blobs = Set<String>()

            func emit(_ bytes: Data) throws {
                hasher.update(data: bytes)
                try handle.write(contentsOf: bytes)
            }

            try emit(Data("[".utf8))
            let cursor = try ClipRow.order(Column("createdAt").asc).fetchCursor(db)
            while var row = try cursor.next() {
                if options.excludeSensitive, row.isSensitive { continue }
                if options.metadataOnly {
                    row.contentText = nil
                    row.contentBlobHash = nil
                }
                if let hash = row.contentBlobHash { blobs.insert(hash) }
                if count > 0 { try emit(Data(",".utf8)) }
                try emit(try encoder.encode(row))
                count += 1
            }
            try emit(Data("]".utf8))
            return (
                count, blobs,
                hasher.finalize().map { String(format: "%02x", $0) }.joined()
            )
        }
    }
}
