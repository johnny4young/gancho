import GanchoDesign
import GanchoKit
import SwiftUI

/// A clip used often enough to be worth keeping, with the three answers.
struct SnippetSuggestionCard: View {
    let item: ClipItem
    let keep: () -> Void
    let never: () -> Void
    let dismiss: () -> Void

    private var title: String { item.title.isEmpty ? item.preview : item.title }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(.callout.weight(.bold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("Used \(item.uses) times")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            FlowLayout(spacing: 4) {
                Button("Keep", action: keep)
                    .ganchoButtonStyle(.primary)
                    .accessibilityIdentifier("snippet-suggestion-keep")
                Button("Never", action: never)
                    .ganchoButtonStyle(.secondary)
                    .accessibilityIdentifier("snippet-suggestion-never")
                Button("Dismiss", action: dismiss)
                    .ganchoButtonStyle(.secondary)
                    .accessibilityIdentifier("snippet-suggestion-dismiss")
            }
            .font(.caption)
        }
        .padding(GanchoTokens.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GanchoTokens.Palette.brandTint, in: shape)
        .overlay(
            shape.strokeBorder(
                GanchoTokens.Palette.brandGreen.opacity(0.35),
                lineWidth: GanchoTokens.Stroke.hairline)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("snippet-suggestion")
    }
}
