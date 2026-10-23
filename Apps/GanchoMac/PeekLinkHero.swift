import GanchoDesign
import SwiftUI

/// Host set large, original URL underneath (including scheme, port and fragment). No remote fetch: the
/// copied URL never leaves the Mac to be rendered.
struct PeekLinkHero: View {
    let parts: ClipLinkParts

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: parts.host)
                .panelFont(size: 24, .bold, design: .rounded)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(verbatim: parts.text)
                .panelFont(.callout, design: .monospaced)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("peek-link-url")
            if let decoded = parts.decoded {
                Text("decoded · \(decoded)")
                    .panelFont(.subheadline, .semibold, design: .monospaced)
                    .foregroundStyle(Color.primary.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 7)
                    .frame(minHeight: 22)
                    .background(Color.primary.opacity(0.07), in: Capsule())
                    .padding(.top, GanchoTokens.Spacing.xxs)
                    .accessibilityIdentifier("peek-link-decoded")
            }
        }
        .textSelection(.enabled)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("peek-link-hero")
    }
}
