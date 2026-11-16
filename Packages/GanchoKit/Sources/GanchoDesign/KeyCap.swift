import SwiftUI

/// A keyboard key drawn as a cap: every action shows its key once.
public struct KeyCap: View {
    public enum Role: Sendable {
        /// Control fill with a hairline, on any neutral surface.
        case neutral
        /// Inside the primary verb: a darker inset on the accent fill.
        case onAccent
    }

    enum Fill { case neutral, onAccent, accent }

    let keys: String
    let fill: Fill
    @Environment(\.panelTypeScale) private var scale

    public init(_ keys: String, role: Role = .neutral) {
        self.keys = keys
        self.fill = role == .neutral ? .neutral : .onAccent
    }

    init(_ keys: String, fill: Fill) {
        self.keys = keys
        self.fill = fill
    }

    public var body: some View {
        switch fill {
        case .neutral:
            cap(ink: GanchoTokens.Palette.ink2, fill: GanchoTokens.Palette.controlFill)
                .overlay(
                    shape.strokeBorder(GanchoTokens.Palette.hairlineStrong, lineWidth: 0.5))
        case .onAccent:
            cap(ink: OnAccentInk(), fill: Color.black.opacity(0.14))
        case .accent:
            cap(ink: OnAccentInk(), fill: AccentFill())
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 5 * scale, style: .continuous)
    }

    private func cap(ink: some ShapeStyle, fill background: some ShapeStyle) -> some View {
        label
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5 * scale)
            .frame(minWidth: 19 * scale, minHeight: 19 * scale)
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
            return .system(.caption2, weight: weight)
        #else
            // The system arrow is wider than the face's glyphs; a smaller size keeps caps even.
            return .system(size: 8.5 * scale, weight: weight)
        #endif
    }

    private var font: Font {
        let weight: Font.Weight = fill == .neutral ? .medium : .semibold
        #if os(iOS)
            return GanchoType.font(.data, size: 10.5, weight: weight, relativeTo: .caption2)
        #else
            return GanchoType.font(.data, size: 10.5 * scale, weight: weight)
        #endif
    }
}

/// The Return key in the accent: it marks the one thing Return does.
public struct ReturnKeyCap: View {
    public init() {}

    public var body: some View {
        KeyCap("↩", fill: .accent).accessibilityHidden(true)
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
