import GanchoAppCore
import GanchoDesign
import KeyboardShortcuts
import SwiftUI

/// The peek column of an empty first-run panel: the whole loop in three keys.
/// The open-panel keys are the recorded shortcut, never a hard-coded one.
struct PanelFirstRunStageView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            Text("The whole loop, three keys")
                .panelFont(.caption, .bold)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            if let shortcut = KeyboardShortcuts.getShortcut(for: .togglePanel) {
                keyCard(
                    PanelFirstRunStage.keycaps(for: shortcut.description),
                    title: "Open the panel from anywhere",
                    detail: "or click the hook in the menu bar")
            } else {
                keyCard([], title: "Click the hook in the menu bar", detail: nil)
            }
            keyCard(
                ["↑", "↓"], title: "Pick a clip, or just type to search",
                detail: "⌘1–9 jumps straight to a row")
            keyCard(["⏎"], title: "Paste where you were typing", detail: "⌥⏎ pastes plain text")
            Spacer(minLength: 0)
        }
        .padding(GanchoTokens.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("panel-first-run-stage")
    }

    private func keyCard(
        _ keys: [String], title: LocalizedStringKey, detail: LocalizedStringKey?
    ) -> some View {
        HStack(spacing: 10) {
            if !keys.isEmpty {
                HStack(spacing: 3) {
                    ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                        Text(verbatim: key)
                            .panelFont(.caption, .bold)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(
                                Color.primary.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                }
                .frame(minWidth: 72, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).panelFont(.callout, .semibold)
                if let detail {
                    Text(detail).panelFont(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, GanchoTokens.Spacing.xs)
        .ganchoSurface(radius: GanchoTokens.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
                .strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline)
        )
        .accessibilityElement(children: .combine)
    }
}
