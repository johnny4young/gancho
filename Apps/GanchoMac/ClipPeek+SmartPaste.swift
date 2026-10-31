import Foundation
import GanchoAI
import GanchoDesign
import SwiftUI

extension ClipPeek {
    var translationAvailabilityRequest: TranslationAvailabilityRequest {
        TranslationAvailabilityRequest(
            text: presentedText, enabled: canSmartPaste,
            modelAvailable: model.smartPasteModelAvailable, refresh: translationRefresh)
    }

    func refreshTranslationTargets() async {
        guard canSmartPaste else {
            translationTargets = []
            return
        }
        // Settle first: arrowing through rows must not probe language pairs per row.
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        let requestedText = presentedText
        let targets = try? await model.translationDestinations(requestedText)
        guard !Task.isCancelled, canSmartPaste, presentedText == requestedText else { return }
        translationTargets = targets ?? []
    }

    var translationUnavailableMessage: some View {
        Text(
            "Translation unavailable. Install a language pair on macOS 26 or use an available on-device model."
        )
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("translation-unavailable-message")
    }

    func runSmartPaste(_ action: SmartPasteAction) {
        translationTask?.cancel()
        let request = UUID()
        translationRequestID = request
        actionResult = nil
        translationFailed = false
        isThinking = true
        translationTask = Task {
            let result = await model.smartPaste(presentedText, action: action)
            guard !Task.isCancelled, translationRequestID == request else { return }
            isThinking = false
            actionResult = result ?? String(localized: "Couldn’t run that — try again.")
        }
    }

    func runTranslate(to target: Locale.Language) {
        translationTask?.cancel()
        let request = UUID()
        translationRequestID = request
        actionResult = nil
        translationFailed = false
        isThinking = true
        translationTask = Task {
            let result = await model.smartTranslate(presentedText, to: target)
            guard !Task.isCancelled, translationRequestID == request else { return }
            isThinking = false
            translationFailed = result == nil
            actionResult = result
        }
    }

}
