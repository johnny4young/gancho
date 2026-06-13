import AppIntents
import GanchoKit

/// Pin/unpin from Shortcuts — same store, same free-tier rule the UI uses.
struct PinClipIntent: AppIntent {
    static let title: LocalizedStringResource = "Pin Clip"
    static let description = IntentDescription("Pins a clip so it never expires.")

    @Parameter(title: "Clip")
    var clip: ClipEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = try IntentStore.open()
        let pinCount = try await store.pinnedCount()
        guard PinLimits.canPin(currentPinCount: pinCount, isPro: false) else {
            return .result(dialog: "Free plan pin limit reached.")
        }
        try await store.setPinned(id: clip.id, true)
        return .result(dialog: "Pinned.")
    }
}
