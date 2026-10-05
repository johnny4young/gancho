import Darwin
import Foundation

/// The database writer and the filesystem cannot share a SQLite transaction.
/// This cross-process lease covers binary adoption through row commit, and
/// orphan reference lookup through deletion, on the same stable lock inode.
final class BlobOwnershipLease: @unchecked Sendable {
    private var descriptor: Int32

    private init(for directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent(".ownership.lock").path
        descriptor = open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
    }

    static func acquire(for directory: URL) async throws -> BlobOwnershipLease {
        let lease = try BlobOwnershipLease(for: directory)
        while !lease.tryLock() {
            let failure = errno
            guard failure == EWOULDBLOCK || failure == EINTR else {
                throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
            }
            // Never block Swift's cooperative executor while another task owns
            // the lease across a GRDB await. Cancellation keeps unprovable bytes.
            try await Task.sleep(for: .milliseconds(10))
        }
        try Task.checkCancellation()
        return lease
    }

    static func tryAcquire(for directory: URL) throws -> BlobOwnershipLease? {
        let lease = try BlobOwnershipLease(for: directory)
        if lease.tryLock() { return lease }
        let failure = errno
        guard failure == EWOULDBLOCK else {
            throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
        }
        return nil
    }

    func tryLock() -> Bool { flock(descriptor, LOCK_EX | LOCK_NB) == 0 }

    func release() {
        guard descriptor >= 0 else { return }
        _ = flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }

    deinit { release() }
}

extension GRDBClipboardStore {
    func acquireBlobOwnership() async throws -> BlobOwnershipLease {
        try await BlobOwnershipLease.acquire(for: blobsForMaintenance.directory)
    }
}
