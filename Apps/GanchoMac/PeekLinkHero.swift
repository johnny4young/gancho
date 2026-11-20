import GanchoDesign
import SwiftUI

/// A link read locally: site first, the copied URL with its parts named, the
/// decoded parameters, and what each paste key puts down. No remote fetch.
struct PeekLinkHero: View {
    let parts: ClipLinkParts
    let anatomy: LinkAnatomy?
    /// The Markdown form, built by the same function that copies it.
    let markdown: String
    /// A short peek: smaller headline and gaps, same content.
    let isCompact: Bool
    let copyMarkdown: () -> Void
    @Environment(\.panelTypeScale) private var scale

    /// A link with hundreds of parameters still shows a bounded row.
    private static let parameterLimit = 8

    private struct Metrics {
        let stack: CGFloat, headline: CGFloat, segmentGap: CGFloat, bracketGap: CGFloat
        let pasteRows: CGFloat

        static let regular = Metrics(
            stack: GanchoTokens.Spacing.md, headline: 30, segmentGap: 3, bracketGap: 10,
            pasteRows: 10)
        static let compact = Metrics(
            stack: GanchoTokens.Spacing.xs, headline: 24, segmentGap: 2, bracketGap: 8,
            pasteRows: 6)
    }

    private var metrics: Metrics { isCompact ? .compact : .regular }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.stack) {
            Text(headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.6)
                .help(parts.text)
                .accessibilityIdentifier("peek-link-headline")
            if let anatomy {
                anatomyRow(anatomy)
                if !anatomy.parameters.isEmpty || anatomy.fragment != nil { decodedRow(anatomy) }
            }
            Rectangle()
                .fill(GanchoTokens.Palette.hairline)
                .frame(height: GanchoTokens.Stroke.hairline)
            pastesAs
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("peek-link-hero")
    }

    private var headline: AttributedString {
        let size = metrics.headline * scale
        var host = AttributedString(parts.host)
        host.font = GanchoType.font(.ui, size: size, weight: .semibold)
        host.foregroundColor = GanchoTokens.Palette.ink
        var path = AttributedString(anatomy?.path ?? "")
        path.font = GanchoType.font(.ui, size: size)
        path.foregroundColor = GanchoTokens.Palette.ink3
        return host + path
    }

    // MARK: Anatomy

    /// One line, as copied: scheme and host keep their width, and the path,
    /// query and fragment truncate in the middle down to their label.
    private func anatomyRow(_ anatomy: LinkAnatomy) -> some View {
        AnatomyLine {
            ForEach(anatomy.segments) { segment in
                VStack(alignment: .leading, spacing: metrics.segmentGap) {
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
                        .padding(.bottom, metrics.bracketGap)
                        .overlay(alignment: .bottom) {
                            PartBracket()
                                .stroke(
                                    GanchoTokens.Palette.hairline,
                                    lineWidth: GanchoTokens.Stroke.hairline
                                )
                                .frame(height: 5)
                                .padding(.horizontal, 1.5)
                        }
                    label(for: segment.part, in: anatomy).peekCaps(size: 9).fixedSize()
                        .padding(.trailing, GanchoTokens.Spacing.xs)
                }
                .layoutPriority(segment.part.widthPriority)
                .help(segment.text)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label(for: segment.part, in: anatomy))
                .accessibilityValue(Text(verbatim: segment.text))
                .accessibilityAddTraits(.isStaticText)
                .accessibilityIdentifier(segment.part.accessibilityIdentifier)
            }
        }
        .clipped()
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
        return FlowLayout(spacing: 6) {
            Text("DECODED").peekCaps().frame(minHeight: 24)
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
        // Without a text role the group drops its value from the AX tree.
        .accessibilityAddTraits(.isStaticText)
        .accessibilityIdentifier(id)
    }

    // MARK: Pastes as

    private var pastesAs: some View {
        VStack(alignment: .leading, spacing: metrics.pasteRows) {
            Text("PASTES AS").peekCaps()
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
            // No key of its own: the row copies it, as does "md" in the action panel.
            Button(action: copyMarkdown) {
                // A real view, so the empty key slot keeps its width.
                pasteRow(text: markdown, note: "Markdown link", textID: "") {
                    Color.clear.frame(height: 0)
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
        HStack(spacing: GanchoTokens.Spacing.xs) {
            key().frame(width: 34 * scale, alignment: .leading)
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
        }
    }
}

extension LinkAnatomy.Part {
    /// Who keeps its width when the line is short: the scheme, then the host.
    fileprivate var widthPriority: Double {
        switch self {
        case .scheme: 2
        case .host: 1
        case .path, .query, .fragment: 0
        }
    }
}

/// URL parts on one line. Short of room, the lowest layout priority gives up
/// width first, down to each part's minimum, and the line never widens its parent.
nonisolated private struct AnatomyLine: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let widths = widths(within: proposal.width, subviews)
        let height =
            zip(subviews, widths).map {
                $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height
            }.max() ?? 0
        let width = widths.reduce(0, +)
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths(within: bounds.width, subviews)) {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                proposal: ProposedViewSize(width: width, height: nil))
            x += width
        }
    }

    private func widths(within available: CGFloat?, _ subviews: Subviews) -> [CGFloat] {
        var widths = subviews.map { $0.sizeThatFits(.unspecified).width }
        guard let available else { return widths }
        var excess = widths.reduce(0, +) - available
        for priority in Set(subviews.map(\.priority)).sorted() where excess > 0 {
            let group = subviews.indices.filter { subviews[$0].priority == priority }
            let slack = group.map {
                max(
                    0,
                    widths[$0]
                        - subviews[$0].sizeThatFits(ProposedViewSize(width: 0, height: nil)).width)
            }
            let total = slack.reduce(0, +)
            guard total > 0 else { continue }
            let share = min(1, excess / total)
            for (index, give) in zip(group, slack) { widths[index] -= give * share }
            excess -= total * share
        }
        return widths
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
