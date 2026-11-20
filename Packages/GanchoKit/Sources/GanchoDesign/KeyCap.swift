import SwiftUI

/// A keyboard key drawn as a cap: every action shows its key once.
public struct KeyCap: View {
    public enum Role: Sendable {
        /// Control fill with a hairline, on any neutral surface.
        case neutral
        /// Inside the primary verb: a darker inset on the accent fill.
        case onAccent
    }

    public enum Size: Sendable {
        /// Inline with text: hints, rows, verbs.
        case regular
        /// A key drawn on its own, as in a lesson: a 32 pt square on a shelf.
        case tile

        var side: CGFloat { self == .tile ? 32 : 19 }
        var radius: CGFloat { self == .tile ? 8 : 5 }
        var padding: CGFloat { self == .tile ? 8 : 5 }
        var fontSize: CGFloat { self == .tile ? 13 : 10.5 }
        var textStyle: Font.TextStyle { self == .tile ? .callout : .caption2 }
    }

    enum Fill { case neutral, onAccent, accent }

    let keys: String
    let fill: Fill
    let size: Size
    @Environment(\.panelTypeScale) private var scale

    public init(_ keys: String, role: Role = .neutral, size: Size = .regular) {
        self.init(keys, fill: role == .neutral ? .neutral : .onAccent, size: size)
    }

    init(_ keys: String, fill: Fill, size: Size) {
        self.keys = keys
        self.fill = fill
        self.size = size
    }

    public var body: some View {
        let isTile = size == .tile
        switch fill {
        case .neutral:
            cap(
                ink: isTile ? GanchoTokens.Palette.ink : GanchoTokens.Palette.ink2,
                fill: isTile
                    ? GanchoTokens.Palette.surface(.card) : GanchoTokens.Palette.controlFill
            )
            .overlay(
                shape.strokeBorder(
                    isTile ? GanchoTokens.Palette.hairline2 : GanchoTokens.Palette.hairline,
                    lineWidth: GanchoTokens.Stroke.hairline)
            )
            .background { if isTile { shelf(GanchoTokens.Palette.hairline2) } }
        case .onAccent:
            cap(ink: OnAccentInk(), fill: Color.black.opacity(0.14))
        case .accent:
            cap(ink: OnAccentInk(), fill: AccentFill())
                .overlay {
                    if isTile {
                        shape.strokeBorder(
                            Color.black.opacity(0.12), lineWidth: GanchoTokens.Stroke.hairline)
                    }
                }
                .background {
                    if isTile {
                        shelf(AccentFill()).overlay(shelf(Color.black.opacity(0.3)))
                    }
                }
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size.radius * scale, style: .continuous)
    }

    /// The key's edge showing below it, so a tile reads as a key to press.
    private func shelf(_ style: some ShapeStyle) -> some View {
        shape.fill(style).offset(y: 2 * scale)
    }

    private func cap(ink: some ShapeStyle, fill background: some ShapeStyle) -> some View {
        label
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, size.padding * scale)
            .frame(minWidth: size.side * scale, minHeight: size.side * scale)
            .foregroundStyle(ink)
            .background(background, in: shape)
    }

    /// Geist Mono draws the Return arrow as a hook, so that symbol takes the system face.
    private var label: Text {
        var text = AttributedString()
        for character in keys {
            var piece = AttributedString(String(character))
            piece.font = Self.usesSystemFace(character) ? systemFont : font
            text += piece
        }
        return Text(text)
    }

    nonisolated static func usesSystemFace(_ character: Character) -> Bool {
        "↩⏎".contains(character)
    }

    private var systemFont: Font {
        let weight: Font.Weight = fill == .neutral ? .medium : .semibold
        #if os(iOS)
            return .system(size.textStyle, weight: weight)
        #else
            return .system(size: size.fontSize * scale, weight: weight)
        #endif
    }

    private var font: Font {
        let weight: Font.Weight = fill == .neutral ? .medium : .semibold
        #if os(iOS)
            return GanchoType.font(
                .data, size: size.fontSize, weight: weight, relativeTo: size.textStyle)
        #else
            return GanchoType.font(.data, size: size.fontSize * scale, weight: weight)
        #endif
    }
}

/// The Return key in the accent: it marks the one thing Return does.
public struct ReturnKeyCap: View {
    let size: KeyCap.Size

    public init(size: KeyCap.Size = .regular) {
        self.size = size
    }

    public var body: some View {
        KeyCap("↩", fill: .accent, size: size).accessibilityHidden(true)
    }
}

/// The live-capture dot. Decorative: the state it marks carries its own label.
public struct LiveDot: View {
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    public init(size: CGFloat = 7) {
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(GanchoTokens.Palette.accentText)
            .frame(width: size, height: size)
            .shadow(
                color: colorScheme == .dark ? GanchoTokens.Palette.accent.opacity(0.8) : .clear,
                radius: 4
            )
            .accessibilityHidden(true)
    }
}
