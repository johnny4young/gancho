import Foundation
import GanchoKit

/// The store-open decision tree both shells inlined in their initializers.
///
/// Each one asked the same two questions in its own order and answered them
/// with its own spelling, and the two differences that produced are not alike.
///
/// The ENCRYPTION difference is live on every throwaway launch and deliberate:
/// macOS encrypts so its UI tests exercise the real open path, iOS does not so
/// a simulator run never reaches the user's App Group Keychain. It survives
/// here as ``Configuration/throwawayIsEncrypted``.
///
/// The PRECEDENCE difference — macOS checked the throwaway hook first, iOS the
/// ephemeral one — was neither deliberate nor reachable: it shows only when a
/// launch passes both flags, and none does. Unreachable and, until this type,
/// unreadable without opening both initializers side by side.
///
/// The decision is separated from the open on purpose. ``request(arguments:)``
/// is pure, so the precedence is unit-testable without a filesystem, a
/// Keychain, or an app; ``open(_:configuration:)`` is the part that touches
/// disk and is left thin enough to read at a glance.
public enum StoreBootstrap {
    /// What a launch's arguments ask for, before anything is opened.
    public enum Request: String, Sendable, Equatable, CaseIterable {
        /// `-use-temp-durable-store`: a real GRDB store in a fresh temp
        /// directory, so UI tests get durable semantics without touching the
        /// user's data.
        case throwaway
        /// `-force-ephemeral-store`: no durable store at all, so the "history
        /// isn't being saved" warning path is drivable by a UI test.
        case ephemeral
        /// The user's real store.
        case production
    }

    /// What a shell needs to open its own store, and nothing more.
    public struct Configuration: Sendable {
        /// Where the user's real store lives.
        ///
        /// A closure, not a URL, so a launch that never opens the production
        /// store never asks for it: iOS resolves an App Group container here,
        /// and a UI test on the throwaway path has no business querying the
        /// simulator user's container just to discard the answer.
        public var productionDirectory: @Sendable () -> URL
        /// Keychain access group for the production passphrase. iOS shares one
        /// with its extensions; macOS has none to share and passes nil.
        public var keychainAccessGroup: String?
        /// Whether the THROWAWAY store is encrypted. Deliberately per-shell:
        /// macOS encrypts so its UI tests exercise the real open path, iOS does
        /// not so a simulator run never reaches the user's App Group Keychain.
        public var throwawayIsEncrypted: Bool
        /// Prefix for the throwaway directory, kept distinct per shell so a
        /// stale one is attributable.
        public var throwawayDirectoryPrefix: String

        public init(
            productionDirectory: @escaping @Sendable () -> URL,
            keychainAccessGroup: String? = nil,
            throwawayIsEncrypted: Bool,
            throwawayDirectoryPrefix: String
        ) {
            self.productionDirectory = productionDirectory
            self.keychainAccessGroup = keychainAccessGroup
            self.throwawayIsEncrypted = throwawayIsEncrypted
            self.throwawayDirectoryPrefix = throwawayDirectoryPrefix
        }
    }

    /// The outcome of one open.
    public struct Opened: Sendable {
        /// The durable store, or nil when the launch asked for the ephemeral
        /// fallback OR the open failed. The caller decides what to substitute,
        /// because the two shells hold different in-memory types.
        public let durable: GRDBClipboardStore?
        /// The directory the store was opened in: the throwaway temp directory
        /// or the production location, and nil only when ephemeral.
        ///
        /// Reported even when ``durable`` is nil, because a failed open still
        /// happened somewhere — macOS anchors its MCP config directory to this,
        /// and anchoring it to success instead would move the config file when
        /// the store failed to open.
        public let directory: URL?

        public init(durable: GRDBClipboardStore?, directory: URL?) {
            self.durable = durable
            self.directory = directory
        }
    }

    /// Which store this launch asks for.
    ///
    /// Throwaway wins over ephemeral: a test that went to the trouble of asking
    /// for a real temp store means it, and the ephemeral flag is the blunter
    /// instrument. Nothing passes both today, so this ordering is a decision
    /// recorded for the first caller that does.
    public static func request(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Request {
        if arguments.contains("-use-temp-durable-store") { return .throwaway }
        if arguments.contains("-force-ephemeral-store") { return .ephemeral }
        return .production
    }

    /// How a durable store is actually opened.
    ///
    /// Injectable, and not only for symmetry: the production opener reads — and
    /// CREATES when absent — the user's real database key via
    /// `KeychainPassphraseStore`, so a unit test must never reach it. Injecting
    /// is also
    /// the only way to exercise the failed-open contract at all, since the
    /// alternative is breaking someone's actual store to watch what happens.
    public typealias Opener =
        @Sendable (
            _ directory: URL, _ encrypted: Bool, _ keychainAccessGroup: String?
        ) -> GRDBClipboardStore?

    /// The real opener. Every failure becomes nil rather than a throw, because
    /// both shells already surface the in-memory fallback to the user through
    /// `storageIsEphemeral` — swallowing it here is what makes that warning
    /// reachable instead of a crash.
    public static let liveOpener: Opener = { directory, encrypted, keychainAccessGroup in
        encrypted
            ? try? GRDBClipboardStore.encrypted(
                directory: directory, keychainAccessGroup: keychainAccessGroup)
            : try? GRDBClipboardStore(directory: directory)
    }

    /// Opens the store this request describes. Never throws.
    public static func open(
        _ request: Request,
        configuration: Configuration,
        opener: Opener = liveOpener
    ) -> Opened {
        switch request {
        case .ephemeral:
            return Opened(durable: nil, directory: nil)
        case .throwaway:
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "\(configuration.throwawayDirectoryPrefix)-\(UUID().uuidString)",
                    isDirectory: true)
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            // No access group: the throwaway store is per-launch and disposable,
            // and both shells opened it without one.
            return Opened(
                durable: opener(directory, configuration.throwawayIsEncrypted, nil),
                directory: directory)
        case .production:
            let directory = configuration.productionDirectory()
            return Opened(
                durable: opener(directory, true, configuration.keychainAccessGroup),
                directory: directory)
        }
    }
}
