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
                    .ignoresSafeArea()
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
                Text("Keyboard shortcuts").font(.headline)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("panel-shortcuts-close-button")
            }
            shortcutLine(["↑", "↓"], "Move selection")
            shortcutLine(["→"], "Open actions")
            shortcutLine(["←"], "Back to list")
            shortcutLine(["⏎"], "Paste")
            shortcutLine(["⌥", "⏎"], "Paste without formatting")
            shortcutLine(["⌘", "1–9"], "Paste that numbered clip")
            shortcutLine(["⌘", "P"], "Pin or unpin")
            shortcutLine(["⌘", "S"], "Save as snippet")
            shortcutLine(["⌘", "B"], "Add to board")
            shortcutLine(["⌘", "Y"], "Preview")
            shortcutLine(["⌘", "↑"], "Recall recent searches")
            shortcutLine(["⌘", "A"], "Select all in search")
            shortcutLine(["esc"], "Close")
            shortcutLine(["⌘", "/"], "Show this list")
        }
        .padding(GanchoTokens.Spacing.md)
        .frame(width: 320)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.lg, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: GanchoTokens.Radius.lg, style: .continuous)
                .strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline)
        )
        .shadow(radius: 20, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("panel-shortcuts")
    }

    private func shortcutLine(_ caps: [String], _ label: LocalizedStringKey) -> some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            HStack(spacing: 3) { ForEach(caps, id: \.self) { keycap($0) } }
                .frame(width: 86, alignment: .leading)
            Text(label).font(.callout)
            Spacer(minLength: 0)
        }
    }

    private func keycap(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .frame(minWidth: 18, minHeight: 18)
            .padding(.horizontal, 4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
