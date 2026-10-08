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
        // Each attempt opens a ledger connection and runs a write transaction,
        // so back off instead of polling it every 10 ms for the whole window.
        var delay = Duration.milliseconds(10)
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
            try await Task.sleep(for: delay)
            delay = min(delay * 2, .milliseconds(100))
        }
    }

    static func tryAcquire(for directory: URL) throws -> BlobOwnershipLease? {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let acquired = try StoreProcessOwnership.acquire(
            in: directory, scope: .blob, exclusive: true)
        guard let ownership = acquired else { return nil }
        return BlobOwnershipLease(ownership: ownership)
    }

    func release() { ownership.release() }
}

extension GRDBClipboardStore {
    func insertionRow(_ item: ClipItem, content: ClipContent?) throws -> ClipRow {
        var row = ClipRow(item: item)
        switch content {
        case .text(let text): row.contentText = text
        case .binary(let data, let typeIdentifier):
            row.contentBlobHash = try blobsForMaintenance.write(data)
            row.contentTypeIdentifier = typeIdentifier
        case .fileReferences(let paths):
            row.contentText = paths.joined(separator: "\n")
            row.contentTypeIdentifier = "public.file-url"
        case nil: break
        }
        return row
    }

    func acquireBlobOwnership() async throws -> BlobOwnershipLease {
        try await BlobOwnershipLease.acquire(for: blobOwnershipDirectory())
    }

    /// Only binary content adopts a content-addressed blob, so only it can race
    /// an orphan sweep. Text, file references and metadata never take the
    /// cross-process lease: a long import, restore or sync page holding it must
    /// never turn an ordinary text capture into a `busy` failure.
    func acquireBlobOwnership(
        adopting contents: some Sequence<ClipContent?>
    ) async throws -> BlobOwnershipLease? {
        guard contents.contains(where: Self.adoptsBlob) else { return nil }
        return try await acquireBlobOwnership()
    }

    static func adoptsBlob(_ content: ClipContent?) -> Bool {
        if case .binary? = content { return true }
        return false
    }
}
