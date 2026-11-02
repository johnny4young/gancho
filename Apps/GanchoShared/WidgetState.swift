import AppIntents
import ClipboardCore
import Foundation
import GanchoKit
import WidgetKit

#if canImport(UIKit)
    import UIKit
#endif

/// What the widgets and the Live Activity share with the app through the App
/// Group: the board the large widget shows, when sync last finished, and the
/// pasteboard's change count when "ready to paste" went up. No content.
nonisolated enum WidgetState {
    private static let boardKey = "widget-board-id"
    private static let syncedKey = "widget-synced-at"
    private static let changeCountKey = "live-activity-change-count"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedInbox.appGroupID) ?? .standard
    }

    static var boardID: UUID? {
        get { defaults.string(forKey: boardKey).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: boardKey) }
    }

    /// Nil while sync is off, so the widget shows no sync age.
    static var syncedAt: Date? {
        get { defaults.object(forKey: syncedKey) as? Date }
        set { defaults.set(newValue, forKey: syncedKey) }
    }

    static var readyChangeCount: Int? {
        get { defaults.object(forKey: changeCountKey) as? Int }
        set { defaults.set(newValue, forKey: changeCountKey) }
    }
}

/// The large widget's board chip: shows that board's clips, or all of them.
struct ShowWidgetBoardIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Board in Widget"
    static let isDiscoverable = false

    @Parameter(title: "Board") var boardID: String?

    init() {}
    init(boardID: UUID?) { self.boardID = boardID?.uuidString }

    func perform() async throws -> some IntentResult {
        WidgetState.boardID = boardID.flatMap(UUID.init(uuidString:))
        return .result()
    }
}

/// "Copy again" on the Live Activity: puts the clip back on the pasteboard,
/// through the same safe delivery as Share, so a protected or expired clip
/// copies nothing. Runs in the app's process.
struct CopyClipAgainIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Copy Again"
    static let isDiscoverable = false
    /// Nothing reaches the pasteboard from a locked iPhone.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Clip") var clipID: String

    init() {}
    init(clipID: UUID) { self.clipID = clipID.uuidString }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if canImport(UIKit)
            guard let id = UUID(uuidString: clipID), let store = try? IntentStore.open(),
                let payload = await ClipSafeDelivery.load(
                    id: id, metadata: { try await store.item(id: $0) },
                    content: { try await store.content(for: $0) })
            else { return .result() }
            switch payload.content {
            case .text(let text): UIPasteboard.general.string = text
            case .fileReferences(let paths):
                UIPasteboard.general.string = paths.joined(separator: "\n")
            case .binary(let data, let type):
                UIPasteboard.general.setData(data, forPasteboardType: type)
            }
            WidgetState.readyChangeCount = UIPasteboard.general.changeCount
        #endif
        return .result()
    }
}
