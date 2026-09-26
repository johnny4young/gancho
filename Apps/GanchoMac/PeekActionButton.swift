import GanchoDesign
import SwiftUI

/// One navigable action in the peek. The action list is the keyboard
/// surface: ↑↓ move among these, Enter runs the focused one, click runs it.
struct PeekAction: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let symbol: String
    /// A shorter label for the dock's narrow buttons; nil uses `title`.
    var shortTitle: LocalizedStringKey?
    /// The key hint under a dock button. Dock actions have one; the Dev
    /// Action chips don't.
    var shortcut: String?
    let run: () -> Void
}

/// A semantic button shared by the peek's dock and developer-action chips.
/// The enclosing peek owns arrow navigation; buttons keep native accessibility activation.
struct PeekActionButton: View {
    enum Style {
        case dock(isPrimary: Bool)
        case chip
    }

    let action: PeekAction
    let style: Style
    let isFocused: Bool
    let run: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var motion: Animation? {
        GanchoMotion.animation(GanchoMotion.quick, reduceMotion: reduceMotion)
    }

    var body: some View {
        Button(action: run) {
            switch style {
            case .dock(let isPrimary): dockLabel(isPrimary: isPrimary)
            case .chip: chipLabel
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        // Focus ring, hover wash and the pin ↔ unpin glyph all settle rather
        // than snap; the glyph swap also bounces once so the toggle registers.
        .animation(motion, value: isFocused)
        .animation(motion, value: isHovered)
        .animation(motion, value: action.symbol)
        .focusable(false)
        .help(action.title)
        .accessibilityLabel(Text(action.title))
        .accessibilityIdentifier(action.id)
        .id(action.id)
    }

    private func dockLabel(isPrimary: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
        return VStack(spacing: 3) {
            Image(systemName: action.symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(height: 18)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: action.symbol)
            Text(action.shortTitle ?? action.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(verbatim: action.shortcut ?? "")
                .font(.caption2.monospaced())
                .opacity(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(
            isPrimary
                ? AnyShapeStyle(GanchoTokens.Palette.accent)
                : isFocused
                    ? AnyShapeStyle(GanchoTokens.Palette.accent.opacity(0.18))
                    : isHovered
                        ? AnyShapeStyle(.quaternary.opacity(0.7))
                        : AnyShapeStyle(.clear), in: shape
        )
        .foregroundStyle(isPrimary ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
        .overlay(
            shape.strokeBorder(
                isFocused ? AnyShapeStyle(.primary) : AnyShapeStyle(.clear),
                lineWidth: GanchoTokens.Stroke.focus)
        )
        .contentShape(Rectangle())
    }

    private var chipLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: action.symbol).font(.caption2)
            Text(action.title).font(.caption.weight(.medium)).lineLimit(1)
        }
        .padding(.horizontal, GanchoTokens.Spacing.xs)
        .padding(.vertical, 4)
        .background(
            isFocused
                ? AnyShapeStyle(GanchoTokens.Palette.accent.opacity(0.18))
                : isHovered
                    ? AnyShapeStyle(.tertiary.opacity(0.5))
                    : AnyShapeStyle(.quaternary), in: Capsule()
        )
        .overlay(
            Capsule().strokeBorder(
                isFocused ? AnyShapeStyle(.primary) : AnyShapeStyle(.clear),
                lineWidth: GanchoTokens.Stroke.focus)
        )
        .contentShape(Capsule())
    }
}
