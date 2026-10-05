import Foundation

/// An open database registers its filesystem generation durably. Recovery
/// requires exclusive logical ownership, not a file lock held during suspension.
final class StoreGenerationLease: @unchecked Sendable {
    private let ownership: StoreProcessOwnership
    let directory: URL

    init(in directory: URL, exclusive: Bool) throws {
        let acquired = try StoreProcessOwnership.acquire(
            in: directory, scope: .generation, exclusive: exclusive)
        guard let ownership = acquired else { throw StoreProcessOwnership.Failure.busy }
        self.ownership = ownership
        self.directory = directory.standardizedFileURL.resolvingSymlinksInPath()
    }

    func downgrade() throws { try ownership.downgrade() }
    func release() { ownership.release() }
}

/// Preserves a whole database/blob/thumbnail generation before creating a new
/// namespace. The journal makes every member move idempotent after interruption.
/// A partial or ambiguous generation fails closed; it is never opened as empty.
enum StoreGenerationRecovery {
    static let journalName = ".store-recovery.json"
    static let members = [
        "gancho.sqlite", "gancho.sqlite-wal", "gancho.sqlite-shm",
        "gancho.sqlite.encrypting", "blobs"
    ]

    private struct Journal: Codable {
        var archive: String
        var members: [String]
    }

    static func openLease(
        in directory: URL, checkingPlaintextConversion: Bool = false
    ) throws -> StoreGenerationLease {
        var lease = try StoreGenerationLease(in: directory, exclusive: false)
        let journalURL = directory.appendingPathComponent(journalName)
        let pending = FileManager.default.fileExists(atPath: journalURL.path)
        let converting = try checkingPlaintextConversion && needsPlaintextConversion(in: directory)
        if pending || converting {
            lease.release()
            lease = try StoreGenerationLease(in: directory, exclusive: true)
            // Recheck after exclusive acquisition: another opener may have
            // completed recovery while this shared registration was released.
            if FileManager.default.fileExists(atPath: journalURL.path) {
                try resume(in: directory)
            }
            if !checkingPlaintextConversion { try lease.downgrade() }
        }
        return lease
    }

    private static func needsPlaintextConversion(in directory: URL) throws -> Bool {
        let database = directory.appendingPathComponent("gancho.sqlite")
        let manager = FileManager.default
        if !manager.fileExists(atPath: database.path) {
            return true  // Creation can race a plaintext opener too.
        }
        let handle = try FileHandle(forReadingFrom: database)
        defer { try? handle.close() }
        return try handle.read(upToCount: 16) == Data("SQLite format 3\u{0}".utf8)
    }

    static func archive(
        in directory: URL, suffix: String,
        afterMove: (String) throws -> Void = { _ in }
    ) throws {
        let lease = try StoreGenerationLease(in: directory, exclusive: true)
        defer { withExtendedLifetime(lease) {} }
        let manager = FileManager.default
        let journalURL = directory.appendingPathComponent(journalName)
        if manager.fileExists(atPath: journalURL.path) {
            try resume(in: directory, afterMove: afterMove)
            return
        }
        let archiveName = ".unreadable-\(suffix)"
        let archive = directory.appendingPathComponent(archiveName, isDirectory: true)
        try manager.createDirectory(
            at: archive, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let present = members.filter {
            manager.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
        guard present.contains("gancho.sqlite") else { throw CocoaError(.fileReadNoSuchFile) }
        let journal = Journal(archive: archiveName, members: present)
        try JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
        let handle = try FileHandle(forWritingTo: journalURL)
        try handle.synchronize()
        try handle.close()
        try resume(in: directory, afterMove: afterMove)
    }

    static func resume(
        in directory: URL, afterMove: (String) throws -> Void = { _ in }
    ) throws {
        let manager = FileManager.default
        let journalURL = directory.appendingPathComponent(journalName)
        guard manager.fileExists(atPath: journalURL.path) else { return }
        let journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: journalURL))
        guard journal.archive.hasPrefix(".unreadable-"),
            !journal.archive.contains("/"), !journal.archive.contains(".."),
            Set(journal.members).count == journal.members.count,
            journal.members.contains("gancho.sqlite"),
            journal.members.allSatisfy({ members.contains($0) })
        else { throw CocoaError(.fileReadCorruptFile) }
        let archive = directory.appendingPathComponent(journal.archive, isDirectory: true)
        let attributes = try archive.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard attributes.isDirectory == true, attributes.isSymbolicLink != true
        else { throw CocoaError(.fileReadCorruptFile) }
        for name in journal.members {
            let source = directory.appendingPathComponent(name)
            let destination = archive.appendingPathComponent(name)
            let sourceExists = manager.fileExists(atPath: source.path)
            let archived = manager.fileExists(atPath: destination.path)
            guard sourceExists != archived else { throw CocoaError(.fileReadCorruptFile) }
            if sourceExists {
                try manager.moveItem(at: source, to: destination)
                try afterMove(name)
            }
        }
        try manager.removeItem(at: journalURL)
    }
}
