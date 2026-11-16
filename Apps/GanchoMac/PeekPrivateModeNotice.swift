import GanchoDesign
import SwiftUI

/// The peek in Private Mode: a hatched stage that says why nothing shows, and
/// that pasting still works.
struct PeekPrivateModeNotice: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.lg, style: .continuous)
        VStack(spacing: GanchoTokens.Spacing.xs) {
            Image(systemName: "eye.slash")
                .panelFont(size: 20)
                .foregroundStyle(GanchoTokens.Palette.ink2)
                .accessibilityHidden(true)
            Text("Previews hidden while Private Mode is on.")
                .panelFont(size: 19, design: .serif)
                .foregroundStyle(GanchoTokens.Palette.ink)
            Text("Pasting still works; only new copies are skipped.")
                .panelFont(.caption)
                .foregroundStyle(GanchoTokens.Palette.ink3)
        }
        .multilineTextAlignment(.center)
        .padding(GanchoTokens.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { RedactionHatch() }
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(
                GanchoTokens.Palette.hairline, lineWidth: GanchoTokens.Stroke.hairline)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("peek-private-mode")
    }
}
