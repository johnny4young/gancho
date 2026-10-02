import Foundation
import GanchoAI
import GanchoDesign
import SwiftUI

extension ClipDetailView {
    var translationAvailabilityRequest: TranslationAvailabilityRequest {
        TranslationAvailabilityRequest(
            text: fullText, enabled: canSmartPaste,
            modelAvailable: model.smartPasteModelAvailable, refresh: translationRefresh)
    }

    func refreshTranslationTargets() async {
        guard canSmartPaste else {
            translationTargets = []
            return
        }
        let requestedText = fullText
        let targets = try? await model.translationDestinations(requestedText)
        guard !Task.isCancelled, canSmartPaste, fullText == requestedText else { return }
        translationTargets = targets ?? []
    }

    var translationUnavailableMessage: some View {
        Text(
            "Translation unavailable. Install the language pair in Translate settings or enable Apple Intelligence."
        )
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("translation-unavailable-message")
    }

    func runSmartPaste(_ action: SmartPasteAction) {
        translationTask?.cancel()
        let request = UUID()
        translationRequestID = request
        smartResult = nil
        translationFailed = false
        isThinking = true
        translationTask = Task {
            let result = await model.smartPaste(fullText, action: action)
            guard !Task.isCancelled, translationRequestID == request else { return }
            isThinking = false
            smartResult = result ?? String(localized: "Couldn’t run that — try again.")
        }
    }

    func runTranslate(to target: Locale.Language) {
        translationTask?.cancel()
        let request = UUID()
        translationRequestID = request
        smartResult = nil
        translationFailed = false
        isThinking = true
        translationTask = Task {
            let result = await model.smartTranslate(fullText, to: target)
            guard !Task.isCancelled, translationRequestID == request else { return }
            isThinking = false
            translationFailed = result == nil
            smartResult = result
        }
    }

}
