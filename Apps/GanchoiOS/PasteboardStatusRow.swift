import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// The pasteboard status on the capture screen. gancho senses the clipboard's
/// TYPE via `detectPatterns` — no read, no "pasted from" banner — and says so.
/// With something on the clipboard it is a card that names the sensed kind and
/// points at the system Paste control in the bottom bar, the one-tap "yes,
/// save this"; after a save it offers to open the clip for a few seconds. An
/// empty clipboard keeps the one-line row.
struct PasteboardStatusRow: View {
    @Environment(IOSAppModel.self) private var model
    @State private var showsInfo = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var sensed: SensedClipboard {
        SensedClipboard(
            hasContent: model.hints.hasContent, probableWebURL: model.hints.probableWebURL,
            probableWebSearch: model.hints.probableWebSearch, number: model.hints.number)
    }

    var body: some View {
        // The one-line row already reflows at the accessibility sizes, where a
        // card would grow taller than the screen above the list.
        if sensed == .empty || dynamicTypeSize.isAccessibilitySize { compactRow } else { card }
    }

    private var card: some View {
        HStack(spacing: GanchoTokens.Spacing.sm) {
            tile
            VStack(alignment: .leading, spacing: 3) {
                title.fixedSize(horizontal: false, vertical: true)
                statusLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
            infoButton
        }
        .padding(.vertical, 10)
        .padding(.leading, GanchoTokens.Spacing.sm)
        .background(
            GanchoTokens.Palette.accentTint,
            in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.lg, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: GanchoTokens.Radius.lg, style: .continuous)
                .strokeBorder(
                    GanchoTokens.Palette.accent.opacity(0.25),
                    lineWidth: GanchoTokens.Stroke.hairline)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pasteboard-status-card")
    }

    private var tile: some View {
        let tint = GanchoTokens.Palette.kindTint(for: sensed.tintKind)
        return Image(systemName: sensed.symbolName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ReadableInk(base: tint))
            .frame(width: 36, height: 36)
            .background(
                tint.opacity(0.16),
                in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.card, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    /// A note while one shows, "Saved" once this copy is captured, the privacy
    /// claim before that. A note keeps its kind's symbol, tint and spoken value.
    @ViewBuilder private var statusLine: some View {
        if let note = model.saveNote {
            Label(note.text, systemImage: note.kind.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ReadableInk(base: note.kind.tint))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(note.text))
                .accessibilityValue(note.kind.accessibilityValue)
                .accessibilityIdentifier("save-note")
        } else if alreadyCaptured {
            Label("Saved", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(GanchoTokens.Palette.accentInk)
        } else {
            // The glyph flows with the text, so a wrapped line never strands it.
            Text(
                "\(Image(systemName: "shield.lefthalf.filled")) \(Text("Sensed, not read — nothing is saved until you tap Paste"))"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Open while the fresh save can still be opened; before a save, a pointer
    /// at the Paste control. The pointer is not a button: only the system
    /// control saves without the paste banner.
    @ViewBuilder private var trailing: some View {
        if offersOpen {
            openButton
        } else if !alreadyCaptured {
            VStack(spacing: 2) {
                Image(systemName: "arrow.down").font(.callout.weight(.semibold))
                Text("Paste").font(.caption2.weight(.bold))
            }
            .foregroundStyle(GanchoTokens.Palette.accentInk)
            .accessibilityHidden(true)
        }
    }

    private var offersOpen: Bool {
        model.recentPasteSave?.offersOpen(now: .now, currentChangeCount: model.hints.changeCount)
            ?? false
    }

    private var openButton: some View {
        Button("Open") { model.openRecentPasteSave() }
            .font(.subheadline.weight(.semibold))
            .ganchoTextButton()
            .frame(minWidth: GanchoTokens.HitTarget.touch, minHeight: GanchoTokens.HitTarget.touch)
            .accessibilityLabel(Text("Open the saved clip"))
            .accessibilityIdentifier("pasteboard-saved-open")
    }

    private var compactRow: some View {
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
                if offersOpen { openButton }
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
                    if offersOpen { openButton }
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
            .font(sensed == .empty ? .subheadline.weight(.medium) : .subheadline.weight(.semibold))
            .accessibilityIdentifier("pasteboard-status-title")
    }

    private var infoButton: some View {
        Button {
            showsInfo = true
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.tertiary)
                // A 44 pt target at every text size, not just the glyph.
                .frame(
                    minWidth: GanchoTokens.HitTarget.touch, minHeight: GanchoTokens.HitTarget.touch
                )
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
                    .foregroundStyle(GanchoTokens.Palette.accentInk)
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
        .foregroundStyle(ReadableInk(base: tint))
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
