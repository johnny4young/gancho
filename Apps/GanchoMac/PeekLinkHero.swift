import GanchoDesign
import SwiftUI

/// A link read locally: site first, the copied URL with its parts named, the
/// decoded parameters, and what each paste key puts down. No remote fetch.
struct PeekLinkHero: View {
    let parts: ClipLinkParts
    let anatomy: LinkAnatomy?
    /// The Markdown form, built by the same function that copies it.
    let markdown: String
    let copyMarkdown: () -> Void
    @Environment(\.panelTypeScale) private var scale

    /// A link with hundreds of parameters still shows a bounded row.
    private static let parameterLimit = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.6)
                .help(parts.text)
                .accessibilityIdentifier("peek-link-headline")
            if let anatomy {
                anatomyRow(anatomy).padding(.top, 21)
                if !anatomy.parameters.isEmpty || anatomy.fragment != nil {
                    // The anatomy row ends in its own 8 pt of wrap spacing.
                    decodedRow(anatomy).padding(.top, 12)
                }
            }
            Hairline().padding(.top, 22)
            pastesAs.padding(.top, 18)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("peek-link-hero")
    }

    private var headline: AttributedString {
        var host = AttributedString(parts.host)
        host.font = GanchoType.font(.ui, size: 31 * scale, weight: .semibold)
        host.tracking = -0.93 * scale
        host.foregroundColor = GanchoTokens.Palette.ink
        var path = AttributedString(anatomy?.path ?? "")
        path.font = GanchoType.font(.ui, size: 31 * scale, weight: .light)
        path.tracking = -0.93 * scale
        path.foregroundColor = GanchoTokens.Palette.ink3
        return host + path
    }

    // MARK: Anatomy

    private func anatomyRow(_ anatomy: LinkAnatomy) -> some View {
        FlowLayout(spacing: 0) {
            ForEach(anatomy.segments) { segment in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: segment.text)
                        .panelFont(
                            size: 12.5, segment.part == .host ? .semibold : .regular,
                            design: .monospaced
                        )
                        .foregroundStyle(
                            segment.part == .host
                                ? GanchoTokens.Palette.ink : GanchoTokens.Palette.ink2
                        )
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .padding(.bottom, 10)
                        .overlay(alignment: .bottom) {
                            PartBracket()
                                .stroke(
                                    GanchoTokens.Palette.hairlineStrong,
                                    lineWidth: GanchoTokens.Stroke.hairline
                                )
                                .frame(height: 5)
                                .padding(.horizontal, 1.5)
                        }
                    label(for: segment.part, in: anatomy).peekCaps(size: 9)
                }
                .padding(.bottom, GanchoTokens.Spacing.xs)
                .help(segment.text)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label(for: segment.part, in: anatomy))
                .accessibilityValue(Text(verbatim: segment.text))
                .accessibilityIdentifier(segment.part.accessibilityIdentifier)
            }
        }
        // A URL reads left to right in every interface language.
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("peek-link-anatomy")
    }

    private func label(for part: LinkAnatomy.Part, in anatomy: LinkAnatomy) -> Text {
        switch part {
        case .scheme: Text("SCHEME")
        case .host: Text("HOST")
        case .path: Text("PATH")
        case .query where anatomy.parameters.isEmpty: Text("QUERY")
        case .query: Text("QUERY · \(anatomy.parameters.count)")
        case .fragment: Text("FRAGMENT")
        }
    }

    private func decodedRow(_ anatomy: LinkAnatomy) -> some View {
        let hidden = anatomy.parameters.count - Self.parameterLimit
        return FlowLayout(spacing: 8) {
            Text("DECODED").peekCaps().frame(minHeight: 24).padding(.trailing, 6)
            ForEach(
                Array(anatomy.parameters.prefix(Self.parameterLimit).enumerated()), id: \.offset
            ) {
                _, parameter in
                chip(parameter.name, parameter.value, id: parameter.accessibilityIdentifier)
            }
            if hidden > 0 { chip("+\(hidden)", "", id: "peek-link-param-more") }
            if let fragment = anatomy.fragment { chip("#", fragment, id: "peek-link-fragment") }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("peek-link-decoded")
    }

    private func chip(_ name: String, _ value: String, id: String) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: name).foregroundStyle(GanchoTokens.Palette.ink3)
            if !value.isEmpty {
                Text(verbatim: value).foregroundStyle(GanchoTokens.Palette.ink)
                    .truncationMode(.middle)
            }
        }
        .panelFont(size: 11.5, design: .monospaced)
        .lineLimit(1)
        .padding(.horizontal, 9)
        .frame(minHeight: 24)
        .background(
            GanchoTokens.Palette.controlFill,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .help(value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityValue(Text(verbatim: value))
        .accessibilityIdentifier(id)
    }

    // MARK: Pastes as

    private var pastesAs: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("PASTES AS").peekCaps().padding(.bottom, 1)
            // Return and ⌥Return write the same text for a link: plain paste
            // only strips rich representations, and a link has none.
            pasteRow(text: parts.text, note: "link", textID: "peek-link-url") { ReturnKeyCap() }
                .textSelection(.enabled)
                .accessibilityElement(children: .contain)
                .accessibilityHint(Text("Pastes with Return"))
                .accessibilityIdentifier("peek-pastes-as-return")
            pasteRow(text: parts.text, note: "plain text", textID: "peek-pastes-as-plain-text") {
                KeyCap("⌥↩").accessibilityHidden(true)
            }
            .accessibilityElement(children: .contain)
            .accessibilityHint(Text("Pastes with Option-Return"))
            .accessibilityIdentifier("peek-pastes-as-plain")
            // ⌘K opens the action panel, whose "Copy as Markdown link" this row runs too.
            Button(action: copyMarkdown) {
                pasteRow(text: markdown, note: "Markdown link", textID: "") {
                    KeyCap("⌘K").accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel(Text("Markdown link"))
            .accessibilityValue(Text(verbatim: markdown))
            .accessibilityIdentifier("peek-pastes-as-markdown")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("peek-pastes-as")
    }

    private func pasteRow(
        text: String, note: LocalizedStringKey, textID: String,
        @ViewBuilder key: () -> some View
    ) -> some View {
        HStack(spacing: 0) {
            key().frame(width: 44 * scale, alignment: .leading)
            Text(verbatim: text)
                .panelFont(size: 11.5, design: .monospaced)
                .foregroundStyle(GanchoTokens.Palette.ink2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(text)
                .accessibilityIdentifier(textID)
            Text(note)
                .panelFont(size: 11)
                .foregroundStyle(GanchoTokens.Palette.ink3)
                .padding(.leading, GanchoTokens.Spacing.sm)
        }
    }
}

/// The open bracket under a URL part: left, bottom and right edges.
nonisolated private struct PartBracket: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}
