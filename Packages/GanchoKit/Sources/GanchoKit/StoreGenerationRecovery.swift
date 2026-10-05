import Darwin
import Foundation

/// An open database pins its filesystem generation. Recovery requires an
/// exclusive cross-process lease, so it cannot move bytes beneath another pool.
final class StoreGenerationLease: @unchecked Sendable {
    private var descriptor: Int32

    init(in directory: URL, exclusive: Bool) throws {
        let path = directory.appendingPathComponent(".store-generation.lock").path
        descriptor = open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        guard flock(descriptor, (exclusive ? LOCK_EX : LOCK_SH) | LOCK_NB) == 0 else {
            let failure = errno
            close(descriptor)
            descriptor = -1
            throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EBUSY)
        }
    }

    func downgrade() throws {
        guard flock(descriptor, LOCK_SH | LOCK_NB) == 0 else { throw POSIXError(.EBUSY) }
    }

    func release() {
        guard descriptor >= 0 else { return }
        _ = flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }

    deinit { release() }
}

/// Preserves a whole database/blob/thumbnail generation before creating a new
/// namespace. The journal makes every member move idempotent after interruption.
/// A partial or ambiguous generation fails closed; it is never opened as empty.
enum StoreGenerationRecovery {
    static let journalName = ".store-recovery.json"
    static let members = [
        "gancho.sqlite", "gancho.sqlite-wal", "gancho.sqlite-shm", "gancho.sqlite.encrypting", "blobs"
    ]

    private struct Journal: Codable {
        var archive: String
        var members: [String]
    }

    static func openLease(in directory: URL) throws -> StoreGenerationLease {
        let lease = try StoreGenerationLease(in: directory, exclusive: false)
        guard FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(journalName).path)
        else { return lease }
        // Release the shared descriptor before acquiring exclusive ownership.
        lease.release()
        return try resumeLease(in: directory)
    }

    private static func resumeLease(in directory: URL) throws -> StoreGenerationLease {
        let exclusive = try StoreGenerationLease(in: directory, exclusive: true)
        try resume(in: directory)
        try exclusive.downgrade()
        return exclusive
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
