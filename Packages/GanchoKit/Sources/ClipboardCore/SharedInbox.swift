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
    /// `key` is the store's blob encryption key (both sides already read it
    /// from the shared keychain to open the encrypted DB). With a key,
    /// deposits are AES-GCM sealed and drains unseal; without one they are
    /// plaintext JSON — production callers should always pass the key.
    public init(directory: URL, key: Data? = nil) {
        self.directory = directory
        self.key = key
    }

    /// Inbox inside the App Group container, or nil when the entitlement is
    /// missing (misconfigured target) — callers surface that, never crash.
    /// Pass the store's blob encryption key so deposits are sealed at rest.
    public static func inAppGroup(key: Data? = nil) -> SharedInbox? {
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

    /// Reads and removes all pending captures, oldest first (file creation
    /// date). Unreadable files are deleted too — a poison capture must not
    /// wedge the inbox forever.
    public func drain() throws -> [PasteboardCapture] {
        try drainPrepared().map(\.capture)
    }

    /// Prepared drain: unseals (sealed deposits) then decodes the envelope,
    /// tolerating LEGACY files — plaintext pre-sealing deposits AND
    /// bare-capture pre-envelope deposits — so an app update never loses
    /// queued shares.
    public func drainPrepared() throws -> [PreparedCapture] {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.creationDateKey])
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }

        let ordered = files.sorted { lhs, rhs in
            let lhsDate =
                (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let rhsDate =
                (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return lhsDate < rhsDate
        }

        var captures: [PreparedCapture] = []
        for file in ordered {
            if let raw = try? Data(contentsOf: file), let data = openedPayload(raw) {
                if let prepared = try? JSONDecoder().decode(PreparedCapture.self, from: data) {
                    captures.append(prepared)
                } else if let legacy = try? JSONDecoder().decode(
                    PasteboardCapture.self, from: data)
                {
                    captures.append(PreparedCapture(capture: legacy))
                }
            }
            try? FileManager.default.removeItem(at: file)
        }
        return captures
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
