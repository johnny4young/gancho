import GanchoDesign
import SwiftUI

/// The peek in Private Mode: says why nothing shows, and that pasting still works.
struct PeekPrivateModeNotice: View {
    var body: some View {
        VStack(spacing: GanchoTokens.Spacing.xxs) {
            Text("Previews hidden while Private Mode is on.")
            Text("Pasting still works; only new copies are skipped.")
        }
        .panelFont(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, GanchoTokens.Spacing.md)
        .padding(.vertical, GanchoTokens.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            GanchoTokens.Palette.surface(.card),
            in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.lg, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: GanchoTokens.Radius.lg, style: .continuous)
                .strokeBorder(.separator)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("peek-private-mode")
    }
}
