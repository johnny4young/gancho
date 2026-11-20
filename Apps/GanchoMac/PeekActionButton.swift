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
    /// The key drawn beside a verb. Dock actions have one; of a secret's
    /// verbs, only the reveal does.
    var shortcut: String?
    /// Draws the verb in the danger ink, with no border (Delete now).
    var isDestructive = false
    let run: () -> Void
}

/// A semantic button shared by the peek's dock and a secret's verbs.
/// The enclosing peek owns arrow navigation; buttons keep native accessibility activation.
struct PeekActionButton: View {
    enum Style {
        /// `short` lets the primary verb drop its target when the dock is tight.
        case dock(isPrimary: Bool, short: Bool = false)
        /// A secret's verb under its token: hairline-bordered, or plain danger
        /// text when destructive.
        case inline
    }

    /// A dock control's height before the panel's type scale; the dock row is this tall.
    static let dockHeight: CGFloat = 34

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
            case .inline: inlineLabel
            }
        }
        .buttonStyle(
            PeekActionFill(
                shape: AnyShape(verbShape), treatment: treatment, isFocused: isFocused,
                isHovered: isHovered)
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

    private var treatment: PeekActionFill.Treatment {
        switch style {
        case .dock(let isPrimary, _): isPrimary ? .primary : .quiet
        case .inline: action.isDestructive ? .danger : .bordered
        }
    }

    private var verbShape: RoundedRectangle {
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
        .frame(height: Self.dockHeight * typeScale)
        .contentShape(Rectangle())
    }

    private var inlineLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: action.symbol).panelFont(size: 12)
            Text(action.title).panelFont(size: 12.5, .medium).lineLimit(1)
            if let shortcut = action.shortcut {
                KeyCap(shortcut).accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 7)
        .frame(height: GanchoTokens.HitTarget.control * typeScale)
        .contentShape(Rectangle())
    }
}

extension PeekActionButton.Style {
    fileprivate var isPrimary: Bool {
        if case .dock(let isPrimary, _) = self { return isPrimary }
        return false
    }

    fileprivate var isShort: Bool {
        if case .dock(_, let short) = self { return short }
        return false
    }
}

/// The verbs' fill under the shared state rule: the primary steps the accent
/// for hover and pressed with its ink; the others take a neutral wash;
/// arrow-key focus draws the 2 pt ring 2 pt outside.
private struct PeekActionFill: ButtonStyle {
    enum Treatment {
        /// The lime Return verb.
        case primary
        /// A dock verb: ink2 until hovered or focused.
        case quiet
        /// A secret's reveal: ink inside a hairline.
        case bordered
        /// Delete now: danger text, no border.
        case danger
    }

    let shape: AnyShape
    let treatment: Treatment
    let isFocused: Bool
    let isHovered: Bool

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
                style.treatment == .primary && isPressed
                    ? GanchoMotion.pressScale(reduceMotion: reduceMotion) : 1
            )
            .animation(GanchoMotion.press, value: isPressed)
    }

    private var step: Double {
        isPressed ? ButtonStates.pressedStep : style.isHovered ? ButtonStates.hoverStep : 0
    }

    private var ink: Color {
        switch style.treatment {
        case .danger: GanchoTokens.Palette.danger
        case .quiet where !style.isHovered && !style.isFocused: GanchoTokens.Palette.ink2
        default: GanchoTokens.Palette.ink
        }
    }

    @ViewBuilder private var filled: some View {
        if style.treatment == .primary {
            label.ganchoPrimaryVerb(in: style.shape, step: step)
        } else {
            let wash = isPressed ? 0.09 : style.isHovered ? 0.05 : 0
            label
                .background(Color.primary.opacity(wash), in: style.shape)
                .overlay {
                    if style.treatment == .bordered {
                        style.shape.stroke(
                            GanchoTokens.Palette.hairline2,
                            lineWidth: GanchoTokens.Stroke.hairline)
                    }
                }
                .foregroundStyle(ink)
        }
    }
}
