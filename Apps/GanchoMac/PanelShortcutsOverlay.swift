import GanchoDesign
import SwiftUI

/// Modal keyboard reference for the panel. It is intentionally a standalone
/// presentation component so the main panel owns only whether it is visible,
/// not the reference card's layout or dismissal affordances.
struct PanelShortcutsOverlay: View {
    @Binding var isPresented: Bool

    var body: some View {
        if isPresented {
            ZStack {
                Color.black.opacity(0.18)
                    .contentShape(Rectangle())
                    .onTapGesture { isPresented = false }
                shortcutsCard
            }
            .transition(.opacity)
        }
    }

    private var shortcutsCard: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            HStack {
                Text("Keyboard shortcuts").panelFont(.headline)
                Spacer()
                IconActionButton(
                    "Close", systemImage: "xmark.circle.fill",
                    identifier: "panel-shortcuts-close-button"
                ) {
                    isPresented = false
                }
                .foregroundStyle(.secondary)
            }
            // A short panel scrolls the list; the header and its Close stay put.
            ViewThatFits(in: .vertical) {
                shortcutRows
                ScrollView { shortcutRows }.scrollBounceBehavior(.basedOnSize)
            }
        }
        .padding(GanchoTokens.Spacing.md)
        .frame(width: 320)
        .ganchoSurface(radius: GanchoTokens.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: GanchoTokens.Radius.lg, style: .continuous)
                .strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline)
        )
        .ganchoElevation(.overlay, cornerRadius: GanchoTokens.Radius.lg)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("panel-shortcuts")
        .padding(.vertical, GanchoTokens.Spacing.md)
    }

    private var shortcutRows: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            shortcutLine(["↑", "↓"], "Move selection")
            shortcutLine(["⇧", "↑", "↓"], "Extend selection")
            shortcutLine(["⌘"], "Click to select several clips")
            shortcutLine(["→"], "Open actions")
            shortcutLine(["←"], "Back to list")
            shortcutLine(["⏎"], "Paste")
            shortcutLine(["⌥", "⏎"], "Paste without formatting")
            shortcutLine(["⌘", "1–9"], "Paste that numbered clip")
            shortcutLine(["⌘", "P"], "Pin or unpin")
            shortcutLine(["⌘", "S"], "Save as snippet")
            shortcutLine(["⇧", "⌘", "S"], "Save search as a filter")
            shortcutLine(["⇥"], "Complete a filter")
            shortcutLine(["⌫"], "Delete (in actions)")
            shortcutLine(["⌘", "B"], "Add to board")
            shortcutLine(["⇧", "⌘", "B"], "Add to last board")
            shortcutLine(["⌥", "⌘", "⏎"], "Add to paste stack")
            shortcutLine(["⌘", "Y"], "Preview")
            shortcutLine(["⌘", "G"], "List or gallery")
            shortcutLine(["⇧", "⌘", "C"], "Copy text from image")
            shortcutLine(["⌘", "↑"], "Recall recent searches")
            shortcutLine(["⌘", "A"], "Select all in search")
            shortcutLine(["esc"], "Close")
            shortcutLine(["⌘", "/"], "Show this list")
        }
    }

    private func shortcutLine(_ caps: [String], _ label: LocalizedStringKey) -> some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            HStack(spacing: 3) { ForEach(caps, id: \.self) { keycap($0) } }
                .frame(width: 86, alignment: .leading)
            Text(label).panelFont(.callout)
            Spacer(minLength: 0)
        }
    }

    private func keycap(_ text: String) -> some View {
        Text(verbatim: text)
            .panelFont(size: 11, .semibold, design: .rounded)
            .frame(minWidth: 18, minHeight: 18)
            .padding(.horizontal, 4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
