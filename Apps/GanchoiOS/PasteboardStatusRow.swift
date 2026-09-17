import GanchoDesign
import SwiftUI

/// The pasteboard status row on the capture screen. gancho senses the
/// clipboard's TYPE via `detectPatterns` — no read, no "pasted from" banner —
/// and says so in a chip that carries contrast; the explanation lives behind
/// the info button. The one-tap "yes, save this" is the system paste control
/// in the bottom bar, next to search, where the thumb already is. Privacy is
/// the function, not an apology.
struct PasteboardStatusRow: View {
    @Environment(IOSAppModel.self) private var model
    @State private var showsInfo = false

    var body: some View {
        // One line while the chip, the sensed type and the info button all
        // fit; otherwise the chip takes its own line and the type wraps beside
        // the button. A single squeezed line let Spanish, the accessibility
        // text sizes and long notes shrink the type to nothing and push the
        // button off screen.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: GanchoTokens.Spacing.xs) {
                chip(wraps: false)
                title
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                infoButton
            }
            VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xxs) {
                chip(wraps: true)
                // Centered, not top-aligned: the button's 44 pt frame would
                // otherwise sit visibly below a one-line type.
                HStack(spacing: GanchoTokens.Spacing.xs) {
                    title
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    infoButton
                }
            }
        }
    }

    /// The state pill: a status note while one shows, "Saved" once the copy on
    /// the clipboard is captured, the privacy claim before that. A note takes
    /// the symbol and tint of its kind and states the kind as its accessibility
    /// value, so an error never reads as a success and color is never the only
    /// signal.
    @ViewBuilder private func chip(wraps: Bool) -> some View {
        if let note = model.saveNote {
            statusChip(
                Text(note.text), systemImage: note.kind.symbolName, tint: note.kind.tint,
                wraps: wraps
            )
            .accessibilityValue(note.kind.accessibilityValue)
            .accessibilityIdentifier("save-note")
        } else if alreadyCaptured {
            statusChip(
                Text("Saved"), systemImage: "checkmark.circle.fill",
                tint: GanchoTokens.Palette.success, wraps: wraps)
        } else {
            statusChip(
                Text("Sensed, not read"), systemImage: "shield.lefthalf.filled",
                tint: GanchoTokens.Palette.success, wraps: wraps)
        }
    }

    private var title: some View {
        Text(senseTitle)
            .font(.subheadline.weight(.medium))
            .accessibilityIdentifier("pasteboard-status-title")
    }

    private var infoButton: some View {
        Button {
            showsInfo = true
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.tertiary)
                // A 44 pt target at every text size, not just the glyph.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("How Gancho senses your clipboard"))
        .accessibilityIdentifier("pasteboard-info")
        .popover(isPresented: $showsInfo, arrowEdge: .top) {
            Label {
                Text(
                    "Gancho never reads your clipboard on its own. It only sees the type until you tap Paste."
                )
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(GanchoTokens.Palette.accent)
            }
            .padding(GanchoTokens.Spacing.md)
            .frame(width: 300)
            .presentationCompactAdaptation(.popover)
        }
    }

    /// State pill in `tint`. On one line it is a capsule; when it has to wrap it
    /// becomes a rounded rectangle, so a second line never spills past a curve.
    private func statusChip(
        _ text: Text, systemImage: String, tint: Color, wraps: Bool
    ) -> some View {
        Label {
            text
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.caption2.weight(.semibold))
        .labelStyle(.titleAndIcon)
        .foregroundStyle(tint)
        // ONE element, labelled by its text. Left to SwiftUI, the identifier
        // and value land on the symbol child, whose label is the symbol's own
        // ("Selected" for a checkmark): VoiceOver would read the icon, and a
        // test would too, instead of "Saved".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .fixedSize(horizontal: !wraps, vertical: true)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            tint.opacity(0.14),
            in: wraps
                ? AnyShape(
                    RoundedRectangle(cornerRadius: GanchoTokens.Radius.lg, style: .continuous))
                : AnyShape(Capsule()))
    }

    /// True when the copy currently on the clipboard is the one we just saved
    /// (matched by the pasteboard's change counter — metadata, no read).
    private var alreadyCaptured: Bool {
        model.lastCapturedChangeCount != nil
            && model.hints.changeCount == model.lastCapturedChangeCount
    }

    /// What `detectPatterns` sensed, as a title — derived without reading.
    private var senseTitle: LocalizedStringKey {
        guard model.hints.hasContent else { return "Pasteboard is empty" }
        if model.hints.probableWebURL { return "Link on your clipboard" }
        if model.hints.probableWebSearch { return "Search text on your clipboard" }
        if model.hints.number { return "Number on your clipboard" }
        return "Something on your clipboard"
    }
}

/// How each kind of status note reads.
extension CaptureStatusNote.Kind {
    fileprivate var symbolName: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .limit: "exclamationmark.circle.fill"
        case .failure: "exclamationmark.triangle.fill"
        }
    }

    fileprivate var tint: Color {
        switch self {
        case .success: GanchoTokens.Palette.success
        case .limit: GanchoTokens.Palette.warning
        case .failure: GanchoTokens.Palette.danger
        }
    }

    /// Spoken after the note's text, so VoiceOver users hear the outcome that
    /// the symbol and tint show.
    fileprivate var accessibilityValue: Text {
        switch self {
        case .success: Text("Done")
        case .limit: Text("Limit reached")
        case .failure: Text("Error")
        }
    }
}
