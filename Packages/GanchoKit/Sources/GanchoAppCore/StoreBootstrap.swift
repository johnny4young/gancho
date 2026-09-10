import Foundation
import GanchoKit

/// The store-open decision tree both shells inlined in their initializers.
///
/// Each one asked the same two questions in its own order and answered them
/// with its own spelling, which is how the two drifted: macOS checked the
/// throwaway hook first and encrypted it, iOS checked the ephemeral hook first
/// and did not. Neither difference was reachable — no launch passes both flags
/// — but only reading both initializers side by side could tell you that.
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

    /// Opens the store this request describes.
    ///
    /// Never throws: every failure degrades to the in-memory fallback, which
    /// both shells already surface to the user through `storageIsEphemeral`.
    /// Swallowing it here rather than at each call site is why that warning is
    /// reachable at all.
    public static func open(_ request: Request, configuration: Configuration) -> Opened {
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
            let store =
                configuration.throwawayIsEncrypted
                ? try? GRDBClipboardStore.encrypted(directory: directory)
                : try? GRDBClipboardStore(directory: directory)
            return Opened(durable: store, directory: directory)
        case .production:
            let directory = configuration.productionDirectory()
            let store = try? GRDBClipboardStore.encrypted(
                directory: directory, keychainAccessGroup: configuration.keychainAccessGroup)
            return Opened(durable: store, directory: directory)
        }
    }
}
