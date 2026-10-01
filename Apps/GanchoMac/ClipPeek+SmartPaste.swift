import Foundation
import GanchoAI
import GanchoDesign
import OSLog
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

    /// On-device rewrite menu (the design's "Smart paste"): summarize, fix
    /// grammar, change tone, pull key points — the result lands in the box below
    /// for review before pasting.
    var smartPasteMenu: some View {
        Menu {
            ForEach(SmartPasteAction.allCases) { action in
                if action == .redactPII || model.smartPasteModelAvailable {
                    Button {
                        runSmartPaste(action)
                    } label: {
                        Label(LocalizedStringKey(action.titleKey), systemImage: action.symbolName)
                    }
                    .accessibilityIdentifier("smart-paste-\(action.id.lowercased())-action")
                }
            }
            if !translationTargets.isEmpty {
                Divider()
                Menu {
                    ForEach(translationTargets) { destination in
                        let code = destination.code
                        Button(LanguageName.localized(code: code)) {
                            runTranslate(to: Locale.Language(identifier: code))
                        }
                        .disabled(!destination.isAvailable)
                        .accessibilityIdentifier("translation-target-\(code)")
                    }
                } label: {
                    Label("Translate to", systemImage: "globe")
                }
                .accessibilityIdentifier("translation-destinations-menu")
            }
            if !translationTargets.contains(where: { $0.isAvailable }) {
                Text("Install a language pair (macOS 26+) or use an available on-device model.")
            }
            Divider()
            Label("Runs on your Mac — nothing leaves the device.", systemImage: "lock.shield")
        } label: {
            Label("Smart paste", systemImage: "sparkles")
                .panelFont(.body, .medium)
                .padding(.horizontal, GanchoTokens.Spacing.sm)
                .padding(.vertical, GanchoTokens.Spacing.xxs)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .ganchoSurface(radius: GanchoTokens.Radius.md)
        .disabled(isThinking)
        .accessibilityIdentifier("smart-paste-menu")
    }

    private func runSmartPaste(_ action: SmartPasteAction) {
        actionResult = nil
        isThinking = true
        Task {
            let result = await model.smartPaste(presentedText, action: action)
            isThinking = false
            actionResult = result ?? String(localized: "Couldn’t run that — try again.")
        }
    }

    private func runTranslate(to target: Locale.Language) {
        translationDiagnosticPhase("action-entered")
        translationTask?.cancel()
        let request = UUID()
        translationRequestID = request
        actionResult = nil
        translationFailed = false
        isThinking = true
        translationTask = Task {
            translationDiagnosticPhase("task-entered")
            let result = await model.smartTranslate(presentedText, to: target)
            translationDiagnosticPhase("engine-returned")
            guard !Task.isCancelled, translationRequestID == request else {
                translationDiagnosticPhase("result-invalidated")
                return
            }
            isThinking = false
            translationFailed = result == nil
            actionResult = result
            translationDiagnosticPhase("result-applied")
        }
    }

    func translationDiagnosticPhase(_ phase: String) {
        #if DEBUG
            let arguments = CommandLine.arguments
            guard arguments.contains("-use-temp-durable-store"),
                arguments.contains("-ui-test-installed-translation"),
                let index = arguments.firstIndex(of: "-translation-diagnostic-nonce"),
                arguments.indices.contains(index + 1),
                let nonce = UUID(uuidString: arguments[index + 1])
            else { return }
            Logger(
                subsystem: "com.johnny4young.gancho.translation-diagnostic", category: "lifecycle"
            ).notice(
                "request \(nonce.uuidString, privacy: .public) uptime \(ProcessInfo.processInfo.systemUptime, privacy: .public) phase \(phase, privacy: .public)"
            )
        #endif
    }

}
