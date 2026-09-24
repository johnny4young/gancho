import Foundation

/// Persistence for a sync transport's opaque state. The shared app controller
/// owns the file location while concrete transports decide what bytes mean.
public struct SyncStateStore: Sendable {
    public let load: @Sendable () -> Data?
    public let save: @Sendable (Data) throws -> Void

    public init(
        load: @escaping @Sendable () -> Data?,
        save: @escaping @Sendable (Data) throws -> Void
    ) {
        self.load = load
        self.save = save
    }

    /// Missing/unreadable state permits a refetch, but failed writes throw:
    /// callers must not claim a checkpoint was durably saved when it was not.
    public static func file(at url: URL) -> SyncStateStore {
        SyncStateStore(
            load: { try? Data(contentsOf: url) },
            save: { try $0.write(to: url, options: .atomic) })
    }
}
