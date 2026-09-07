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
    public init(directory: URL, key: Data? = nil) {
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

    /// What one drain did, so the host app can report a content-free health
    /// note instead of losing captures silently.
    public struct DrainSummary: Sendable, Equatable {
        /// Captures handed to the app, oldest first.
        public var captures: [PreparedCapture]
        /// Files whose bytes were read but could not be opened or decoded.
        /// These were deleted: a poison capture must not wedge the inbox.
        public var poisoned: Int
        /// Files that could not be read at all and were LEFT IN PLACE for the
        /// next drain — possibly mid-write, or momentarily unreadable under
        /// data protection.
        public var deferred: Int

        public init(captures: [PreparedCapture], poisoned: Int = 0, deferred: Int = 0) {
            self.captures = captures
            self.poisoned = poisoned
            self.deferred = deferred
        }
    }

    /// Reads and removes all pending captures, oldest first (file creation
    /// date).
    public func drain() throws -> [PasteboardCapture] {
        try drainPrepared().map(\.capture)
    }

    /// Prepared drain, discarding the health counters.
    public func drainPrepared() throws -> [PreparedCapture] {
        try drainReportingHealth().captures
    }

    /// Prepared drain: unseals (sealed deposits) then decodes the envelope,
    /// tolerating LEGACY files — plaintext pre-sealing deposits AND
    /// bare-capture pre-envelope deposits — so an app update never loses
    /// queued shares.
    public func drainReportingHealth() throws -> DrainSummary {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.creationDateKey])
        } catch CocoaError.fileReadNoSuchFile {
            return DrainSummary(captures: [])
        }

        let ordered = files.sorted { lhs, rhs in
            let lhsDate =
                (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let rhsDate =
                (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return lhsDate < rhsDate
        }

        var captures: [PreparedCapture] = []
        var poisoned = 0
        var deferred = 0
        for file in ordered {
            // A file we could not even READ is not poison — it is a capture
            // that may still be mid-write, or briefly unreadable under data
            // protection. Deleting it would silently destroy the user's clip,
            // so leave it for the next drain. Only bytes we DID read and could
            // not make sense of are poison, and those must go or they wedge
            // the inbox forever.
            guard let raw = try? Data(contentsOf: file) else {
                deferred += 1
                continue
            }
            if let data = openedPayload(raw) {
                if let prepared = try? JSONDecoder().decode(PreparedCapture.self, from: data) {
                    captures.append(prepared)
                } else if let legacy = try? JSONDecoder().decode(
                    PasteboardCapture.self, from: data)
                {
                    captures.append(PreparedCapture(capture: legacy))
                } else {
                    poisoned += 1
                }
            } else {
                poisoned += 1
            }
            try? FileManager.default.removeItem(at: file)
        }
        return DrainSummary(captures: captures, poisoned: poisoned, deferred: deferred)
    }

    /// Unwraps one file's payload. Sealed files open with the key; a sealed
    /// file with no/wrong key returns nil and is discarded as poison, same
    /// as unreadable JSON. Unsealed bytes pass through — legacy plaintext
    /// deposits from before sealing landed.
    private func openedPayload(_ raw: Data) -> Data? {
        guard SealedEnvelope.isSealed(raw) else { return raw }
        guard let key else { return nil }
        return try? SealedEnvelope.open(raw, key: key)
    }
}
