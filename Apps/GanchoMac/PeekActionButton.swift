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
    /// Draws the chip's label in the danger ink (Delete now).
    var isDestructive = false
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
    @Environment(\.panelTypeScale) private var typeScale
    @State private var isHovered = false

    private var motion: Animation? {
        GanchoMotion.quick(reduceMotion: reduceMotion)
    }

    var body: some View {
        Button(action: run) {
            switch style {
            case .dock: dockLabel
            case .chip: chipLabel
            }
        }
        .buttonStyle(
            PeekActionFill(
                shape: style.isDock ? AnyShape(dockShape) : AnyShape(Capsule()),
                isPrimary: style.isPrimary, isFocused: isFocused, isHovered: isHovered,
                isChip: !style.isDock)
        )
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

    private var dockShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
    }

    private var dockLabel: some View {
        VStack(spacing: 3) {
            Image(systemName: action.symbol)
                .panelFont(size: 15, .semibold)
                .frame(height: 18 * typeScale)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                // A constant value never triggers the discrete bounce.
                .symbolEffect(.bounce, value: reduceMotion ? "" : action.symbol)
            Text(action.shortTitle ?? action.title)
                .panelFont(.caption, .semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(verbatim: action.shortcut ?? "")
                .panelFont(.caption2, design: .monospaced)
                .opacity(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    private var chipLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: action.symbol).panelFont(.caption)
            Text(action.title).panelFont(.subheadline, .medium).lineLimit(1)
        }
        .foregroundStyle(
            action.isDestructive
                ? AnyShapeStyle(GanchoTokens.Palette.danger) : AnyShapeStyle(.primary)
        )
        .padding(.horizontal, GanchoTokens.Spacing.xs)
        .padding(.vertical, 4)
        .contentShape(Capsule())
    }
}

extension PeekActionButton.Style {
    fileprivate var isDock: Bool {
        if case .dock = self { return true }
        return false
    }

    fileprivate var isPrimary: Bool {
        if case .dock(let isPrimary) = self { return isPrimary }
        return false
    }
}

/// The dock and chip fill under the shared state rule: the primary steps its
/// green for hover and pressed with dark ink; the others take a neutral wash;
/// arrow-key focus draws the 2 pt ring 2 pt outside.
private struct PeekActionFill: ButtonStyle {
    let shape: AnyShape
    let isPrimary: Bool
    let isFocused: Bool
    let isHovered: Bool
    let isChip: Bool

    func makeBody(configuration: Configuration) -> some View {
        PeekActionFillBody(style: self, isPressed: configuration.isPressed) {
            configuration.label
        }
    }
}

private struct PeekActionFillBody<Label: View>: View {
    let style: PeekActionFill
    let isPressed: Bool
    @ViewBuilder let label: Label
    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let fill = fillColor
        label
            .background(fill, in: style.shape)
            .foregroundStyle(
                style.isPrimary
                    ? AnyShapeStyle(ContrastingForeground(on: fill)) : AnyShapeStyle(.primary)
            )
            .padding(style.isFocused ? GanchoTokens.Stroke.focus * 1.5 : 0)
            .overlay {
                if style.isFocused {
                    style.shape.stroke(
                        GanchoTokens.Palette.accentInk, lineWidth: GanchoTokens.Stroke.focus)
                }
            }
            .padding(style.isFocused ? -GanchoTokens.Stroke.focus * 1.5 : 0)
            .scaleEffect(
                style.isPrimary && isPressed
                    ? GanchoMotion.pressScale(reduceMotion: reduceMotion) : 1
            )
            .animation(GanchoMotion.press, value: isPressed)
    }

    private var step: Double {
        isPressed ? ButtonStates.pressedStep : style.isHovered ? ButtonStates.hoverStep : 0
    }

    private var fillColor: Color {
        if style.isPrimary {
            return Color(
                Contrast.stepped(
                    GanchoTokens.Palette.accent.resolve(in: environment), by: step,
                    lighter: colorScheme == .dark))
        }
        let rest = style.isChip ? 0.05 : 0
        let wash = isPressed ? 0.09 : style.isHovered ? 0.05 + rest : rest
        return Color.primary.opacity(wash)
    }
}
