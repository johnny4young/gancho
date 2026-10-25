import GanchoAI
import GanchoDesign
import GanchoKit
import SwiftUI
import UIKit

extension ClipDetailView {
    /// The deterministic transforms fit any text-like clip and never a masked
    /// secret. Deliberately NO availability gate — they work on every device,
    /// with Apple Intelligence off.
    private var canTransform: Bool {
        isTextLike && !requiresMasking
    }

    /// Dev actions, Transform, Smart Paste and Translate as one chip group, all
    /// on device; a result lands in the box below with its own Copy.
    @ViewBuilder var smartActionsSection: some View {
        let actions =
            (!requiresMasking || (revealed && hasLoadedFullText))
            ? DevActions.actions(for: item.kind) : []
        if !actions.isEmpty || canTransform || canSmartPaste {
            Section {
                FlowLayout(spacing: 6) {
                    if let linkParts {
                        chip("Markdown link") {
                            actionResult = linkParts.markdownLink(title: item.title)
                        }
                        .accessibilityIdentifier("detail-markdown-link")
                    }
                    ForEach(actions) { action in
                        chip(LocalizedStringKey(action.title)) {
                            actionResult = (try? action.transform(fullText)) ?? ""
                        }
                    }
                    if canTransform { transformMenu }
                    if canSmartPaste { smartPasteChips }
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
                results
            } header: {
                HStack {
                    Text("Smart actions")
                    Spacer()
                    Label("on-device", systemImage: "lock.shield")
                        .labelStyle(.titleAndIcon)
                        .textCase(nil)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var transformMenu: some View {
        // Pure text transforms; `.plainText` is the identity — omitted.
        Menu {
            ForEach(PasteTransform.allCases.filter { $0 != .plainText }, id: \.self) { transform in
                Button(LocalizedStringKey(transform.title)) {
                    actionResult = transform.apply(to: fullText)
                }
            }
        } label: {
            chipLabel("Transform", systemImage: "chevron.down", trailingSymbol: true)
        }
        // A menu tints its label with the accent; this chip is a neutral one.
        .tint(.primary)
        .accessibilityIdentifier("transform-menu")
    }

    @ViewBuilder private var smartPasteChips: some View {
        ForEach(SmartPasteAction.allCases) { action in
            if action == .redactPII || model.smartPasteModelAvailable {
                Button {
                    runSmartPaste(action)
                } label: {
                    chipLabel(
                        LocalizedStringKey(action.titleKey), systemImage: "sparkles",
                        intelligent: true)
                }
                .buttonStyle(.plain)
                .disabled(isThinking)
                .accessibilityIdentifier("smart-paste-\(action.id.lowercased())-action")
            }
        }
        if !translationTargets.isEmpty {
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
                chipLabel(
                    "Translate to", systemImage: "chevron.down", trailingSymbol: true,
                    intelligent: true)
            }
            .disabled(isThinking)
            .accessibilityIdentifier("smart-paste-menu")
        }
    }

    @ViewBuilder private var results: some View {
        if canSmartPaste, !translationTargets.isEmpty,
            !translationTargets.contains(where: { $0.isAvailable })
        {
            Text("Install a supported language pair or use an available on-device model.")
                .font(.caption).foregroundStyle(.secondary)
        }
        if translationFailed { translationUnavailableMessage }
        if let actionResult, !actionResult.isEmpty {
            Text(actionResult).font(.body.monospaced()).textSelection(.enabled)
            Button("Copy result", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = actionResult
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
        if isThinking {
            Label("Thinking…", systemImage: "sparkles").foregroundStyle(.secondary)
        } else if let smartResult, !smartResult.isEmpty {
            Text(smartResult).font(.body).textSelection(.enabled)
                .accessibilityIdentifier("intelligence-result-text")
            Button("Copy result", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = smartResult
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    private func chip(_ title: LocalizedStringKey, _ run: @escaping () -> Void) -> some View {
        Button(action: run) { chipLabel(title, systemImage: nil) }
            .buttonStyle(.plain)
    }

    /// A neutral chip for deterministic actions; a green one for intelligence.
    private func chipLabel(
        _ title: LocalizedStringKey, systemImage: String?, trailingSymbol: Bool = false,
        intelligent: Bool = false
    ) -> some View {
        HStack(spacing: 4) {
            if let systemImage, !trailingSymbol {
                Image(systemName: systemImage).font(.caption2)
            }
            Text(title)
            if let systemImage, trailingSymbol {
                Image(systemName: systemImage).font(.caption2)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, GanchoTokens.Spacing.sm)
        .frame(minHeight: 30)
        .foregroundStyle(
            intelligent ? AnyShapeStyle(GanchoTokens.Palette.accentInk) : AnyShapeStyle(.primary)
        )
        .background(
            intelligent
                ? AnyShapeStyle(GanchoTokens.Palette.accentTint) : AnyShapeStyle(.quaternary),
            in: Capsule()
        )
        .contentShape(Capsule())
    }
}
