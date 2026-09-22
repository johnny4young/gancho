import CryptoKit
import Foundation
import GanchoKit

/// File-based capture handoff between the share extension and the host app.
///
/// The extension cannot talk to the app process directly; it drops one JSON
/// file per capture into the shared App Group container and the app drains
/// the folder on activation. Files (not a shared database) on purpose: the
/// extension lives ~seconds and must never contend for the store's locks —
/// GRDB stays single-owner in the app process.
///
/// With a `key`, deposits are sealed via `SealedEnvelope` so queued captures
/// never sit as plaintext in the container between the extension's write and
/// the app's next drain.
public struct SharedInbox: Sendable {
    /// App Group shared by the iOS app and its extensions. Must match the
    /// `com.apple.security.application-groups` entitlement on every target.
    public static let appGroupID = "group.com.johnny4young.gancho"

    private let directory: URL
    private let key: Data?

    /// Injectable directory so behavior is unit-testable without
    /// entitlements; production callers use `inAppGroup(key:)`.
    ///
    /// `key` is the store's content key (`StoreContentKey.load`). With a key,
    /// deposits are AES-GCM sealed and drains unseal. The nil case exists ONLY
    /// so tests can write the legacy plaintext shape that a drain must still
    /// accept; production goes through `inAppGroup(key:)`, which requires one.
    ///
    /// Deliberately INTERNAL. Leaving it public would let any client of this
    /// package construct a keyless inbox and deposit plaintext clipboard
    /// content — the exact exposure the seal exists to prevent — with nothing
    /// but a doc comment discouraging it. The tests reach it through
    /// `@testable`, so the boundary costs them nothing and is enforced by the
    /// compiler rather than by convention.
    init(directory: URL, key: Data? = nil) {
        self.directory = directory
        self.key = key
    }

    /// Inbox inside the App Group container, or nil when the entitlement is
    /// missing (misconfigured target) — callers surface that, never crash.
    ///
    /// `key` is REQUIRED, and deliberately has no default: a deposit made
    /// without it lands as plaintext clipboard content in a container that
    /// survives until the app's next drain. Obtain it from
    /// `StoreContentKey.load(keychainAccessGroup:)`, and if that throws, do
    /// not deposit at all.
    public static func inAppGroup(key: Data) -> SharedInbox? {
        guard
            let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupID)
        else { return nil }
        return SharedInbox(
            directory: container.appendingPathComponent("inbox", isDirectory: true), key: key)
    }

    /// A capture plus the work the extension already did. Tier-0
    /// classification runs INSIDE the extension (deterministic, <5ms, tiny
    /// memory) so the app-side drain doesn't repeat it.
    public struct PreparedCapture: Sendable, Equatable, Codable {
        public var capture: PasteboardCapture
        public var kind: ClipContentKind?

        public init(capture: PasteboardCapture, kind: ClipContentKind? = nil) {
            self.capture = capture
            self.kind = kind
        }
    }

    /// Persists one capture as its own file. Atomic write + UUID name: a
    /// crash mid-write never corrupts neighbors, drains never race writers.
    public func deposit(_ capture: PasteboardCapture) throws {
        try deposit(PreparedCapture(capture: capture))
    }

    public func deposit(_ prepared: PreparedCapture) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("\(UUID().uuidString).json")
        let encoded = try JSONEncoder().encode(prepared)
        let payload = try key.map { try SealedEnvelope.seal(encoded, key: $0) } ?? encoded
        // Data Protection is belt-and-suspenders under the seal: readable
        // after first unlock (drains can run from a background activation)
        // but never off a cold locked device.
        #if os(iOS)
            // File protection is an iOS data-protection feature; the option
            // constants are absent from the macOS SDK, so guard by platform.
            try payload.write(
                to: file,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
            try payload.write(to: file, options: .atomic)
        #endif
    }

    /// Opaque authority to acknowledge exactly the bytes that were read.
    /// Identity includes the existing filename and digest, so legacy names are
    /// supported and a replacement file cannot inherit an earlier receipt.
    public struct Delivery: Sendable, Equatable {
        public let id: String
        public let prepared: PreparedCapture
        fileprivate let fileName: String
        fileprivate let digest: Data
    }

    public struct Cursor: Sendable, Equatable {
        fileprivate let date: Date
        fileprivate let name: String
    }

    public struct ReadSummary: Sendable, Equatable {
        public let deliveries: [Delivery]
        public let poisoned: Int
        public let deferred: Int
        public let undeletable: Int
        /// Continue after this metadata key on the next bounded drain. Nil
        /// resets the scan so earlier deferred/new arrivals are retried too.
        public let nextCursor: Cursor?
    }

    /// Reads at most `limit` candidates without removing good deliveries.
    /// Authentication failures are deferred: wrong keys and damaged sealed
    /// bytes cannot be distinguished safely. Only confirmed invalid plaintext
    /// or successfully authenticated malformed JSON may be discarded.
    public func readPending(after cursor: Cursor? = nil, limit: Int = 64) throws -> ReadSummary {
        let candidates = try orderedCandidates(after: cursor)
        let batch = Array(candidates.prefix(max(1, min(limit, 256))))
        var deliveries: [Delivery] = []
        var poisoned = 0
        var deferred = 0
        var undeletable = 0
        for (file, _) in batch {
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values?.isRegularFile == true, values?.isSymbolicLink != true,
                let raw = try? Data(contentsOf: file)
            else {
                deferred += 1
                continue
            }
            let data: Data
            if SealedEnvelope.isSealed(raw) {
                guard let key, let opened = try? SealedEnvelope.open(raw, key: key) else {
                    deferred += 1
                    continue
                }
                data = opened
            } else {
                data = raw
            }
            let prepared =
                (try? JSONDecoder().decode(PreparedCapture.self, from: data))
                ?? (try? JSONDecoder().decode(PasteboardCapture.self, from: data)).map {
                    PreparedCapture(capture: $0)
                }
            if let prepared {
                let digest = Data(SHA256.hash(data: raw))
                var identity = Data(file.lastPathComponent.utf8)
                identity.append(0)
                identity.append(digest)
                let id = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
                deliveries.append(
                    Delivery(
                        id: id, prepared: prepared, fileName: file.lastPathComponent, digest: digest
                    ))
            } else {
                do {
                    try FileManager.default.removeItem(at: file)
                    poisoned += 1
                } catch { undeletable += 1 }
            }
        }
        return ReadSummary(
            deliveries: deliveries, poisoned: poisoned, deferred: deferred,
            undeletable: undeletable,
            nextCursor: candidates.count > batch.count ? batch.last?.1 : nil)
    }

    /// Call only after an atomic durable insert/receipt or a confirmed receipt
    /// replay. Failure leaves the file for another attempt; absence is already
    /// acknowledged. Never delete a replaced file or traverse a symlink.
    public func acknowledge(_ delivery: Delivery) throws {
        let file = directory.appendingPathComponent(delivery.fileName)
        do {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw CocoaError(.fileReadUnknown)
            }
            let raw = try Data(contentsOf: file)
            guard Data(SHA256.hash(data: raw)) == delivery.digest else {
                throw CocoaError(.fileReadUnknown)
            }
            try FileManager.default.removeItem(at: file)
        } catch CocoaError.fileReadNoSuchFile {
            return
        }
    }

    private func orderedCandidates(after cursor: Cursor?) throws -> [(URL, Cursor)] {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [
                    .creationDateKey, .isRegularFileKey, .isSymbolicLinkKey
                ])
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
        return files.filter { $0.pathExtension == "json" }.map { file in
            (
                file,
                Cursor(
                    date: (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate)
                        ?? .distantPast,
                    name: file.lastPathComponent)
            )
        }.sorted { Self.precedes($0.1, $1.1) }.filter { entry in
            cursor.map { Self.precedes($0, entry.1) } ?? true
        }
    }

    private static func precedes(_ lhs: Cursor, _ rhs: Cursor) -> Bool {
        lhs.date == rhs.date ? lhs.name < rhs.name : lhs.date < rhs.date
    }
}
