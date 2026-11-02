import GanchoDesign
import GanchoKit
import SwiftUI

/// Replaces the toolbar while the list shows the session around one result.
struct PanelContextHeader: View {
    var body: some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Context · 2 min before and after")
                .panelFont(.callout, .semibold)
            Spacer(minLength: GanchoTokens.Spacing.xs)
            Text("esc back to results")
                .panelFont(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background { WindowDragArea() }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("context-header")
    }
}

/// A context row: the time it was first copied, the card, and the match.
struct PanelContextRow<Card: View>: View {
    let item: ClipItem
    let isAnchor: Bool
    @ViewBuilder let card: () -> Card

    var body: some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            Text(item.createdAt, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                .panelFont(.caption2, digits: true)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
            card()
            ZStack {
                if isAnchor {
                    Text("Match")
                        .panelFont(.caption2, .semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .ganchoTintedPill(GanchoTokens.Palette.brandGreen, wash: 0.18)
                        .accessibilityIdentifier("context-match")
                }
            }
            .frame(width: 52)
        }
    }
}
