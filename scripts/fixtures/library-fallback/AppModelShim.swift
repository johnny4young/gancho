import Foundation
import GanchoAppCore
import GanchoKit

// Matches the production store facet declarations. No app composition root.
@MainActor final class AppModel {
    let store: any ClipboardStore
    let fullStore: (any FullClipStore)?
    let toasts = FixtureToasts()
    init(store: any ClipboardStore, fullStore: (any FullClipStore)? = nil) {
        self.store = store
        self.fullStore = fullStore
    }
}

struct GanchoToast { init(message: String) {} }
@MainActor struct FixtureToasts { func show(_ toast: GanchoToast) {} }
