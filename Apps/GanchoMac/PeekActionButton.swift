import GanchoDesign
import SwiftUI

/// One navigable action in the peek. The action list is the keyboard
/// surface: ↑↓ move among these, Enter runs the focused one, click runs it.
struct PeekAction: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let symbol: String
    /// A shorter label for the dock's quiet verbs; nil uses `title`.
    var shortTitle: LocalizedStringKey?
    /// The key drawn beside a dock verb. Dock actions have one; the Dev
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
        /// `short` lets the primary verb drop its target when the dock is tight.
        case dock(isPrimary: Bool, short: Bool = false)
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
        // The focus ring and the hover wash settle rather than snap.
        .animation(motion, value: isFocused)
        .animation(motion, value: isHovered)
        .focusable(false)
        .help(action.title)
        .accessibilityLabel(Text(action.title))
        // The key is drawn as a cap; VoiceOver reads it after the name.
        .accessibilityValue(Text(verbatim: action.shortcut ?? ""))
        .accessibilityIdentifier(action.id)
        .id(action.id)
    }

    private var dockShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
    }

    /// The primary verb spells its whole title while it fits; the quiet ones
    /// use the short one.
    private var dockLabel: some View {
        let isPrimary = style.isPrimary
        return HStack(spacing: isPrimary ? 9 : 6) {
            Text(isPrimary && !style.isShort ? action.title : action.shortTitle ?? action.title)
                .panelFont(size: isPrimary ? 13 : 12.5, isPrimary ? .semibold : .medium)
                .lineLimit(1)
            if let shortcut = action.shortcut {
                KeyCap(shortcut, role: isPrimary ? .onAccent : .neutral)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, isPrimary ? 13 : 7)
        .padding(.trailing, isPrimary ? 8 : 7)
        .frame(height: 34 * typeScale)
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
        if case .dock(let isPrimary, _) = self { return isPrimary }
        return false
    }

    fileprivate var isShort: Bool {
        if case .dock(_, let short) = self { return short }
        return false
    }
}

/// The dock and chip fill under the shared state rule: the primary steps the
/// accent for hover and pressed with its ink; the others take a neutral wash;
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        filled
            .padding(style.isFocused ? GanchoTokens.Stroke.focus * 1.5 : 0)
            .overlay {
                if style.isFocused {
                    style.shape.stroke(
                        GanchoTokens.Palette.ink, lineWidth: GanchoTokens.Stroke.focus)
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

    @ViewBuilder private var filled: some View {
        if style.isPrimary {
            label.ganchoPrimaryVerb(in: style.shape, step: step)
        } else {
            let rest = style.isChip ? 0.05 : 0
            let wash = isPressed ? 0.09 : style.isHovered ? 0.05 + rest : rest
            label
                .background(Color.primary.opacity(wash), in: style.shape)
                .foregroundStyle(
                    style.isChip || style.isHovered || style.isFocused
                        ? GanchoTokens.Palette.ink : GanchoTokens.Palette.ink2)
        }
    }
}
