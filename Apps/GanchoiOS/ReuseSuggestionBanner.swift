import GanchoDesign
import GanchoKit
import SwiftUI

/// A single local curation prompt produced after demonstrated reuse. It carries
/// metadata only; clipboard content never enters presentation state.
struct ReuseSuggestion: Identifiable, Equatable {
    enum Destination: Equatable {
        case board(Pinboard)
        case snippet
    }

    let item: ClipItem
    let destination: Destination

    var id: UUID { item.id }
}

/// Non-modal, dismissible action surface shared by the iPhone and iPad shells.
/// It sits above the current screen rather than interrupting copy with a sheet.
struct ReuseSuggestionBanner: View {
    let suggestion: ReuseSuggestion
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: GanchoTokens.Spacing.sm) {
            Image(systemName: "sparkles")
                .foregroundStyle(GanchoTokens.Palette.accent)
                .accessibilityHidden(true)
            message
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(actionTitle, action: onAccept)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(minHeight: 44)
                .accessibilityLabel(Text(actionAccessibilityLabel))
                .accessibilityIdentifier("reuse-suggestion-action")
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .accessibilityLabel(Text("Dismiss"))
            .accessibilityIdentifier("reuse-suggestion-dismiss")
        }
        .padding(GanchoTokens.Spacing.sm)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
        )
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .padding(.horizontal, GanchoTokens.Spacing.sm)
        .padding(.bottom, GanchoTokens.Spacing.xxs)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reuse-suggestion")
    }

    @ViewBuilder private var message: some View {
        switch suggestion.destination {
        case .board(let board):
            Text("Add to \(board.name)?")
        case .snippet:
            Text("Used 3 times — save as a snippet?")
        }
    }

    private var actionTitle: LocalizedStringKey {
        switch suggestion.destination {
        case .board: "Add"
        case .snippet: "Save"
        }
    }

    private var actionAccessibilityLabel: LocalizedStringKey {
        switch suggestion.destination {
        case .board: "Add"
        case .snippet: "Save as snippet"
        }
    }
}
