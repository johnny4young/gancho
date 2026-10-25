import Foundation
import GRDB

/// What the Privacy Center's Verify finds on this Mac: the SQLCipher build,
/// whether the database file on disk is unreadable without its key, and
/// whether the store just opened with that key.
public struct StoreEncryptionReport: Equatable, Sendable {
    /// The linked SQLCipher version; nil when the build has no codec.
    public let cipherVersion: String?
    /// The database file exists on disk and has a header to check.
    public let fileFound: Bool
    /// The file does not start with SQLite's plaintext header.
    public let fileIsEncrypted: Bool
    /// A read through the keyed connection succeeded.
    public let opensWithKey: Bool

    public init(
        cipherVersion: String?, fileFound: Bool = true, fileIsEncrypted: Bool, opensWithKey: Bool
    ) {
        self.cipherVersion = cipherVersion
        self.fileFound = fileFound
        self.fileIsEncrypted = fileIsEncrypted
        self.opensWithKey = opensWithKey
    }

    public var isVerified: Bool {
        cipherVersion != nil && fileFound && fileIsEncrypted && opensWithKey
    }
}

/// Local, content-free checks the Settings tiles and the Privacy Center show,
/// plus the rows "Forget recent clips" may remove.
public protocol StoreHealthProviding: Sendable {
    func encryptionReport() async -> StoreEncryptionReport
    /// Bytes the database and its sealed blobs take on disk.
    func diskUsage() async -> Int64
    /// Visible clips copied at or after `cutoff` that a recent forget removes:
    /// not snippets, pins or board members, which the user chose to keep.
    func forgettableClips(since cutoff: Date) async throws -> [ClipItem]
}

extension GRDBClipboardStore: StoreHealthProviding {
    static let plaintextHeader = Data("SQLite format 3\u{0}".utf8)

    public func encryptionReport() async -> StoreEncryptionReport {
        let path = writer.path
        let probe: (String?, Bool)? = try? await writer.read { db in
            let version = try String.fetchOne(db, sql: "PRAGMA cipher_version")
            _ = try Int.fetchOne(db, sql: "SELECT count(*) FROM sqlite_master")
            return (version?.isEmpty == false ? version : nil, true)
        }
        let header =
            FileManager.default.fileExists(atPath: path)
            ? (try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)))
                .flatMap { handle in
                    defer { try? handle.close() }
                    return try? handle.read(upToCount: Self.plaintextHeader.count)
                }
            : nil
        return StoreEncryptionReport(
            cipherVersion: probe?.0,
            fileFound: header.map { $0.count == Self.plaintextHeader.count } ?? false,
            fileIsEncrypted: header.map { $0 != Self.plaintextHeader } ?? false,
            opensWithKey: probe?.1 ?? false)
    }

    public func diskUsage() async -> Int64 {
        let path = writer.path
        guard FileManager.default.fileExists(atPath: path) else { return 0 }
        return Self.allocatedSize(of: URL(fileURLWithPath: path).deletingLastPathComponent())
    }

    /// Database, its WAL and the sealed blobs all live in one directory.
    static func allocatedSize(of directory: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey]
        guard
            let files = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: Array(keys))
        else { return 0 }
        var total: Int64 = 0
        for case let url as URL in files {
            total += Int64((try? url.resourceValues(forKeys: keys))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    public func forgettableClips(since cutoff: Date) async throws -> [ClipItem] {
        try await writer.read { db in
            try ClipRow.fetchAll(
                db,
                sql: """
                    SELECT \(ClipRow.metadataSelectionSQL) FROM clip
                    WHERE clip.isArchived = 0 AND clip.isSnippet = 0 AND clip.isPinned = 0
                      AND clip.createdAt >= ?
                      AND clip.id NOT IN (SELECT clipID FROM clip_board)
                    ORDER BY clip.createdAt DESC
                    """,
                arguments: [cutoff]
            ).map(\.item)
        }
    }
}
