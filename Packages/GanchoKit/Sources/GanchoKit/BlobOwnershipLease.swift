import Foundation
import GRDB

/// A committed logical token covers binary adoption through row commit and
/// orphan reference lookup through deletion. No kernel lock or coordinator
/// transaction survives the async boundary. Recovery uses the same coordinator.
final class BlobOwnershipLease: Sendable {
    private let ownership: StoreProcessOwnership

    private init(ownership: StoreProcessOwnership) { self.ownership = ownership }

    static func acquire(for directory: URL) async throws -> BlobOwnershipLease {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while true {
            try Task.checkCancellation()
            do {
                if let lease = try tryAcquire(for: directory) {
                    try Task.checkCancellation()
                    return lease
                }
            } catch let error as DatabaseError {
                guard error.resultCode == .SQLITE_BUSY || error.resultCode == .SQLITE_LOCKED
                else { throw error }
            }
            // Live/suspended/unverifiable owners are not timed out or revoked.
            // Only this request times out, reporting busy with all bytes intact.
            guard ContinuousClock.now < deadline else { throw StoreProcessOwnership.Failure.busy }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    static func tryAcquire(for directory: URL) throws -> BlobOwnershipLease? {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let ownership = try StoreProcessOwnership.acquire(
            in: directory, scope: .blob, exclusive: true)
        else { return nil }
        return BlobOwnershipLease(ownership: ownership)
    }

    func release() { ownership.release() }
}

extension GRDBClipboardStore {
    func acquireBlobOwnership() async throws -> BlobOwnershipLease {
        try await BlobOwnershipLease.acquire(for: blobOwnershipDirectory())
    }
}
