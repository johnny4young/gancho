import Foundation

/// Persistence for a sync transport's opaque state. The shared app controller
/// owns the file location while concrete transports decide what bytes mean.
public struct SyncStateStore: Sendable {
    public let load: @Sendable () -> Data?
    public let save: @Sendable (Data) -> Void

    public init(
        load: @escaping @Sendable () -> Data?,
        save: @escaping @Sendable (Data) -> Void
    ) {
        self.load = load
        self.save = save
    }

    /// File-backed state at `url`. Read/write failures degrade to no saved
    /// state because a lost token can safely force a complete refetch.
    public static func file(at url: URL) -> SyncStateStore {
        SyncStateStore(
            load: { try? Data(contentsOf: url) },
            save: { try? $0.write(to: url, options: .atomic) })
    }
}
