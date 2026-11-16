import SwiftUI

/// Search field with the panel's type-to-search contract: focused state is
/// owned by the caller; every keystroke updates the binding immediately.
public struct SearchField<Leading: View, Trailing: View>: View {
    /// `.card` sits on its own glass surface (a standalone control); `.bare`
    /// is the panel header — larger type, no surface of its own, because a
    /// glass control inside a glass panel reads as nested material.
    public enum Style: Sendable {
        case card, bare
    }

    let promptKey: LocalizedStringKey
    let style: Style
    /// While previews are hidden the magnifier becomes an eye-slash.
    let hidesPreviews: Bool
    @Binding var text: String
    /// Sits between the magnifier and the text: filter chips.
    let leading: Leading
    /// Sits after the clear button: a mode control.
    let trailing: Trailing
    @Environment(\.panelTypeScale) private var scale

    public init(
        _ promptKey: LocalizedStringKey, text: Binding<String>, style: Style = .card,
        hidesPreviews: Bool = false,
        @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing
    ) {
        self.promptKey = promptKey
        self.hidesPreviews = hidesPreviews
        self._text = text
        self.style = style
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        switch style {
        case .card:
            field
                .padding(GanchoTokens.Spacing.xs)
                .ganchoSurface(radius: GanchoTokens.Radius.md)
        case .bare:
            field
                .panelFont(size: 22)
                .tracking(-0.33)
                .padding(.leading, 22)
                .padding(.trailing, 20)
                .frame(height: 61 * scale)
        }
    }

    var glyph: String {
        hidesPreviews ? "eye.slash" : "magnifyingglass"
    }

    /// The panel header leads with the hook; a card keeps the magnifier.
    @ViewBuilder private var leadingGlyph: some View {
        if style == .bare, !hidesPreviews {
            HookMark()
                .fill(GanchoTokens.Palette.ink2)
                .frame(width: 22 * scale, height: 22 * scale)
        } else {
            Image(systemName: glyph)
                .foregroundStyle(.secondary)
                .frame(width: (style == .bare ? 22 : 16) * scale, alignment: .center)
        }
    }

    private var field: some View {
        HStack(spacing: style == .bare ? 14 : GanchoTokens.Spacing.xs) {
            leadingGlyph.accessibilityHidden(true)
            leading
            TextField(promptKey, text: $text)
                .textFieldStyle(.plain)
                .ganchoCaret()
                .autocorrectionDisabled()
                #if os(macOS)
                    .textContentType(nil)
                    .textInputSuggestions { EmptyView() }
                #endif
                // Take the row and left-align: a bare `.plain` TextField on macOS
                // lets the field's intrinsic width shrink to the value, which with
                // the tight spacing clipped the first characters of the prompt
                // ("Se" of "Search…") behind the icon.
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("search-field")
            if !text.isEmpty {
                IconActionButton(
                    "Clear search", systemImage: "xmark.circle.fill", identifier: "search-clear"
                ) {
                    text = ""
                }
                .foregroundStyle(.secondary)
            }
            trailing
        }
    }
}

extension View {
    /// The accent caret of a field that filters what Return runs.
    public func ganchoCaret() -> some View {
        tint(GanchoTokens.Palette.accentText)
    }
}

extension SearchField where Leading == EmptyView, Trailing == EmptyView {
    public init(
        _ promptKey: LocalizedStringKey, text: Binding<String>, style: Style = .card,
        hidesPreviews: Bool = false
    ) {
        self.init(
            promptKey, text: text, style: style, hidesPreviews: hidesPreviews,
            leading: { EmptyView() }, trailing: { EmptyView() })
    }
}
