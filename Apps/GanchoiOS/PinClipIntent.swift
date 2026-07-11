import AppIntents
import GanchoKit

enum PinClipActionAppEnum: String, AppEnum {
    case pin
    case unpin

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Pin action"
    static let caseDisplayRepresentations: [PinClipActionAppEnum: DisplayRepresentation] = [
        .pin: "Pin",
        .unpin: "Unpin"
    ]

    var action: ClipPinAction {
        switch self {
        case .pin: .pin
        case .unpin: .unpin
        }
    }
}

/// Pin/unpin from Shortcuts — same store, same free-tier rule the UI uses.
struct PinClipIntent: AppIntent {
    static let title: LocalizedStringResource = "Pin Clip"
    static let description = IntentDescription("Pins or unpins a clip.")

    @Parameter(title: "Clip")
    var clip: ClipEntity

    @Parameter(title: "Action", default: .pin)
    var action: PinClipActionAppEnum

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = try IntentStore.open()
        let tier = await StoreKitEntitlement.currentTier()
        switch try await ClipPinning.perform(
            action.action, clipID: clip.id, tier: tier, store: store)
        {
        case .pinned:
            return .result(dialog: "Pinned.")
        case .unpinned:
            return .result(dialog: "Unpinned.")
        case .alreadyPinned:
            return .result(dialog: "Already pinned.")
        case .alreadyUnpinned:
            return .result(dialog: "Already unpinned.")
        case .freeLimitReached:
            return .result(dialog: "Free plan pin limit reached.")
        case .clipUnavailable:
            return .result(dialog: "Clip is no longer available.")
        }
    }
}
