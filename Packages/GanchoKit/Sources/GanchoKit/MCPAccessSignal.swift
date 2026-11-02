import Foundation

/// Tells the app that `gancho mcp` logged an access. The notification is the
/// name alone: no object, no user info. The app reads the new ledger rows
/// itself, so a forged post can only make it re-read what is already there.
public enum MCPAccessSignal {
    public static let name = Notification.Name("com.johnny4young.gancho.mcp-access")

    #if os(macOS)
        public static func post(to center: DistributedNotificationCenter = .default()) {
            center.postNotificationName(name, object: nil, userInfo: nil, deliverImmediately: true)
        }
    #endif
}
