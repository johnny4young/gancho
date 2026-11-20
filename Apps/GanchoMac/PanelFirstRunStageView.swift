import GanchoAppCore
import GanchoDesign
import KeyboardShortcuts
import SwiftUI

/// The peek column of an empty first-run panel: the whole loop in three keys.
/// The open-panel keys are the recorded shortcut, never a hard-coded one.
struct PanelFirstRunStageView: View {
    /// Re-read whenever defaults change, so a shortcut recorded while the
    /// lesson is open shows at once.
    @State private var shortcut = KeyboardShortcuts.getShortcut(for: .togglePanel)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("First run · 30 seconds").peekCaps()
            Text("The whole loop, three keys")
                .panelFont(size: 27, design: .serif)
                .foregroundStyle(GanchoTokens.Palette.ink)
                .padding(.top, GanchoTokens.Spacing.xxs)
                .padding(.bottom, GanchoTokens.Spacing.md)
            PanelHairline()
            if let shortcut {
                let caps = PanelFirstRunStage.keycaps(for: shortcut.description)
                keyRow(
                    title: "Open the panel from anywhere",
                    detail: "or click the hook in the menu bar", spokenKeys: Self.spoken(caps)
                ) {
                    ForEach(Array(caps.enumerated()), id: \.offset) { _, key in
                        KeyCap(key, size: .tile)
                    }
                }
            } else {
                keyRow(title: "Click the hook in the menu bar", detail: nil) { EmptyView() }
            }
            keyRow(
                title: "Pick a clip, or just type to search",
                detail: "⌘1–9 jumps straight to a row",
                spokenKeys: String(localized: "Up and Down Arrows")
            ) {
                KeyCap("↑", size: .tile)
                KeyCap("↓", size: .tile)
            }
            // The one accent on this screen: what Return does.
            keyRow(
                title: "Paste where you were typing", detail: "pastes plain text",
                detailKey: "⌥↩", spokenDetail: "Option-Return pastes plain text",
                spokenKeys: String(localized: "Return")
            ) {
                ReturnKeyCap(size: .tile)
            }
            Spacer(minLength: 0)
        }
        .padding(GanchoTokens.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("panel-first-run-stage")
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) {
            _ in
            shortcut = KeyboardShortcuts.getShortcut(for: .togglePanel)
        }
    }

    private func keyRow(
        title: LocalizedStringKey, detail: LocalizedStringKey?, detailKey: String? = nil,
        spokenDetail: LocalizedStringKey? = nil, spokenKeys: String? = nil,
        @ViewBuilder keys: () -> some View
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: GanchoTokens.Spacing.md) {
                HStack(spacing: 5) { keys() }
                    .frame(minWidth: 117, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: spokenKeys ?? ""))
                    .accessibilityHidden(spokenKeys == nil)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).panelFont(.callout, .semibold)
                        .foregroundStyle(GanchoTokens.Palette.ink)
                    if let detail {
                        HStack(spacing: 4) {
                            if let detailKey { KeyCap(detailKey).accessibilityHidden(true) }
                            Text(detail).panelFont(.caption)
                                .foregroundStyle(GanchoTokens.Palette.ink3)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(spokenDetail ?? detail))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, GanchoTokens.Spacing.md)
            PanelHairline()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("panel-first-run-key")
    }

    /// "⇧⌘V" read aloud as "Shift-Command-V".
    private static func spoken(_ caps: [String]) -> String {
        caps.map { cap in
            switch cap {
            case "⌃": String(localized: "Control")
            case "⌥": String(localized: "Option")
            case "⇧": String(localized: "Shift")
            case "⌘": String(localized: "Command")
            default: cap
            }
        }.joined(separator: "-")
    }
}

/// A full-width rule between the rows of a stage.
struct PanelHairline: View {
    var body: some View {
        Rectangle()
            .fill(GanchoTokens.Palette.hairline)
            .frame(height: GanchoTokens.Stroke.hairline)
            .accessibilityHidden(true)
    }
}

/// The empty history's mark: the menu-bar hook hanging from a dashed line.
struct PanelEmptyMark: View {
    static let side: CGFloat = 64
    private static let hook = MenuBarGlyph.mark(side: side)

    var body: some View {
        VStack(spacing: 0) {
            Path { path in
                path.move(to: CGPoint(x: 0.5, y: 0))
                path.addLine(to: CGPoint(x: 0.5, y: 44))
            }
            .stroke(
                GanchoTokens.Palette.ink3,
                style: StrokeStyle(lineWidth: GanchoTokens.Stroke.hairline, dash: [2, 4])
            )
            .frame(width: 1, height: 44)
            // The hook's eye sits right of centre and below the image's top edge.
            .offset(x: Self.side * 2 / 96)
            .padding(.bottom, -Self.side * 11.5 / 96)
            Image(nsImage: Self.hook)
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .frame(width: Self.side, height: Self.side)
                .foregroundStyle(GanchoTokens.Palette.ink)
        }
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "gancho"))
        .accessibilityIdentifier("panel-empty-mark")
    }
}
