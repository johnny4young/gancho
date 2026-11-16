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
    @Binding var text: String
    /// Sits between the magnifier and the text: filter chips.
    let leading: Leading
    /// Sits after the clear button: a mode control.
    let trailing: Trailing

    public init(
        _ promptKey: LocalizedStringKey, text: Binding<String>, style: Style = .card,
        @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing
    ) {
        self.promptKey = promptKey
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
                .panelFont(.title3)
                .padding(.horizontal, GanchoTokens.Spacing.md)
                .padding(.vertical, GanchoTokens.Spacing.sm)
        }
    }

    private var field: some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .center)
                .accessibilityHidden(true)
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
    public init(_ promptKey: LocalizedStringKey, text: Binding<String>, style: Style = .card) {
        self.init(
            promptKey, text: text, style: style, leading: { EmptyView() },
            trailing: { EmptyView() })
    }
}
