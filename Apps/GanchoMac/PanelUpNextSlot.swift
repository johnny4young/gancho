import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// One predicted clip above the list for the app in front; ⌘↩ or a click pastes it.
struct PanelUpNextSlot: View {
    let slot: UpNextSlot
    let appName: String
    let paste: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
        Button(action: paste) {
            HStack(alignment: .center, spacing: GanchoTokens.Spacing.sm) {
                ClipTile(item: slot.item, size: 34, previewsHidden: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Up next · on-device")
                        .textCase(.uppercase)
                        .panelFont(.caption2, .bold)
                        .foregroundStyle(GanchoTokens.Palette.ink2)
                    preview
                        .lineLimit(1)
                        .truncationMode(.tail)
                    reason
                        .panelFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    KeyCap("⌘")
                    KeyCap("↩")
                }
            }
            .padding(.horizontal, GanchoTokens.Spacing.sm)
            .padding(.vertical, GanchoTokens.Spacing.xs)
            .background(.background, in: shape)
            .overlay(
                shape.strokeBorder(
                    GanchoTokens.Palette.ink2, lineWidth: GanchoTokens.Stroke.hairline)
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, GanchoTokens.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Up next: \(title)"))
        .accessibilityValue(reason)
        .accessibilityHint(Text(verbatim: "⌘↩"))
        .accessibilityIdentifier("up-next-slot")
    }

    private var title: String {
        slot.item.title.isEmpty ? ClipSafePresentation.displayText(for: slot.item) : slot.item.title
    }

    @ViewBuilder private var preview: some View {
        let text = ClipSafePresentation.displayText(for: slot.item)
        if slot.item.kind == .code {
            Text(GanchoTokens.Syntax.highlighted(String(text.prefix(240))))
                .panelFont(.callout, design: .monospaced)
        } else {
            Text(verbatim: text).panelFont(.callout)
        }
    }

    private var reason: Text {
        switch slot.reason {
        case .pastedToday(let count):
            Text("Pasted into \(appName) \(count)× today")
        case .pastedRecently(let count):
            Text("Pasted into \(appName) \(count)× in the last 30 days")
        }
    }
}
