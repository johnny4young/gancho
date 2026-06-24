#if os(iOS)
    import ActivityKit
    import Foundation

    /// The Live Activity that surfaces the last captured clip — "ready to paste"
    /// — on the Dynamic Island and lock screen, with its sync state. iOS only
    /// (ActivityKit doesn't exist on macOS), hence the `canImport` fence. The
    /// type is shared so the app starts/updates it and the widget renders it.
    public struct ClipActivityAttributes: ActivityAttributes, Sendable {
        public struct ContentState: Codable, Hashable, Sendable {
            /// Already masked-safe — the app passes `•••` for sensitive clips, so
            /// a secret never reaches the lock screen.
            public var preview: String
            public var kindSymbolName: String
            public var isSensitive: Bool
            public var sync: ClipSyncBadge

            public init(
                preview: String, kindSymbolName: String, isSensitive: Bool, sync: ClipSyncBadge
            ) {
                self.preview = preview
                self.kindSymbolName = kindSymbolName
                self.isSensitive = isSensitive
                self.sync = sync
            }
        }

        public init() {}
    }

    /// A compact sync state for the Live Activity badge — the SyncStatus axis
    /// distilled to what a glanceable surface needs.
    public enum ClipSyncBadge: String, Codable, Hashable, Sendable {
        case local  // sync off / idle — lives on this device
        case syncing
        case pending
        case synced
        case offline
        case paused

        public init(_ status: SyncStatus) {
            switch status {
            case .idle: self = .local
            case .syncing: self = .syncing
            case .pending: self = .pending
            case .upToDate: self = .synced
            case .paused(.offline), .failed(.offline): self = .offline
            case .paused, .failed: self = .paused
            }
        }

        public var symbolName: String {
            switch self {
            case .local: "iphone"
            case .syncing: "arrow.triangle.2.circlepath"
            case .pending: "arrow.up.circle"
            case .synced: "checkmark.icloud"
            case .offline: "icloud.slash"
            case .paused: "pause.circle"
            }
        }

        /// Warning states read amber; synced reads as success; the rest neutral.
        public var emphasis: Emphasis {
            switch self {
            case .synced: .success
            case .offline, .paused: .warning
            case .local, .syncing, .pending: .neutral
            }
        }

        public enum Emphasis: Sendable { case neutral, success, warning }
    }
#endif
