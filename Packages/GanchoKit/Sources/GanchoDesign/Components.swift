import GanchoKit
import SwiftUI

/// Glass surface treatment shared by every component: Liquid Glass when the
/// user allows transparency, a solid readable surface when they don't.
/// Glass-native is a day-1 commitment (the opt-out dies with SDK 27) — the
/// fallback exists for ACCESSIBILITY, not for a legacy look.
public struct GanchoSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    let shape: RoundedRectangle

    public func body(content: Content) -> some View {
        // Increased contrast ALSO opts out of glass: translucency is the
        // main legibility cost, regardless of which setting flagged it.
        // Below macOS/iOS 26 Liquid Glass does not exist, so those systems
        // take the same opaque-material branch accessibility already uses.
        if #available(macOS 26.0, iOS 26.0, *), !reduceTransparency, contrast != .increased {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.background.secondary, in: shape)
        }
    }
}

extension View {
    /// Standard Gancho glass card surface.
    public func ganchoSurface(radius: CGFloat = GanchoTokens.Radius.card) -> some View {
        modifier(
            GanchoSurface(shape: RoundedRectangle(cornerRadius: radius, style: .continuous)))
    }
}

/// Kind badge: distinctive icon + name, colored per family. VoiceOver reads
/// the localized kind name, never "button".
public struct TypeBadge: View {
    /// `.plain` is secondary text; `.pill` sits on a wash of the kind's tint.
    public enum Style: Sendable {
        case plain, pill
    }

    let kind: ClipContentKind
    let style: Style

    public init(kind: ClipContentKind, style: Style = .plain) {
        self.kind = kind
        self.style = style
    }

    public var body: some View {
        let label = Label(LocalizedStringKey(kind.rawValue), systemImage: kind.symbolName)
            .labelStyle(.titleAndIcon)
        switch style {
        case .plain:
            label
                .panelFont(.caption2, .medium)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("type-badge")
        case .pill:
            let tint = GanchoTokens.Palette.kindTint(for: kind)
            label
                .panelFont(.caption, .semibold)
                .foregroundStyle(tint)
                .padding(.horizontal, GanchoTokens.Spacing.xs)
                .padding(.vertical, 3)
                .background(tint.opacity(0.14), in: Capsule())
                .accessibilityIdentifier("type-badge")
        }
    }
}

/// The parts of a link a row tile or the peek hero shows: the host without
/// a leading `www.`, and the complete original URL. Parsed locally from the stored
/// text — no favicon and no metadata fetch, so the URL never leaves the device.
public struct ClipLinkParts: Equatable, Sendable {
    public let host: String
    public let text: String

    public init?(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Oversized links use the ordinary bounded text preview instead of URL parsing.
        guard trimmed.utf8.count <= 4_000,
            let url = URL(string: trimmed), let rawHost = url.host()?.removingPercentEncoding,
            !rawHost.isEmpty
        else { return nil }
        host = rawHost.lowercased().hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        guard !host.isEmpty else { return nil }
        self.text = trimmed
    }
}

extension GanchoTokens.Palette {
    /// Clip-kind family colours (the design's `tokens/colors.css`): the tint
    /// behind a row's icon tile and the filter-rail dots.
    public static func kindTint(for kind: ClipContentKind) -> Color {
        switch kind {
        case .url: kindRGB(0x32, 0xAD, 0xE6)
        case .code, .json, .uuid: kindRGB(0x58, 0x56, 0xD6)
        case .image: kindRGB(0xFF, 0x9F, 0x0A)
        case .fileReference: kindRGB(0x00, 0x7A, 0xFF)
        case .color: kindRGB(0x5A, 0xC8, 0xFA)
        case .jwt, .secret, .creditCard: kindRGB(0xFF, 0x3B, 0x30)
        default: kindRGB(0x8E, 0x8E, 0x93)
        }
    }

    private static func kindRGB(_ red: Int, _ green: Int, _ blue: Int) -> Color {
        Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }
}

/// One clip row/card: kind tile, title/preview (masked kinds render their
/// stored masked preview — the secret never reaches this view), and a trailing
/// meta column (source · time, markers, ⌘N).
public struct ClipCard: View {
    let item: ClipItem
    let isSelected: Bool
    /// Private mode: show ONLY the kind — shoulder surfers and screen
    /// shares see types, never content.
    let previewsHidden: Bool
    /// 1–9 renders the ⌘N quick-paste badge; nil hides it (e.g. the Library,
    /// which has no quick-paste).
    let shortcutNumber: Int?
    /// A pre-loaded thumbnail for image clips; nil falls back to the kind tile.
    let thumbnail: Image?
    /// When set, the selection highlight glides to the newly selected row
    /// instead of appearing on it. Every row of one list passes the same
    /// namespace; only the anchor row claims the gliding highlight.
    let selectionNamespace: Namespace.ID?
    let isSelectionAnchor: Bool
    @Environment(\.panelTypeScale) private var typeScale
    private var tileSize: CGFloat { 36 * typeScale }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.listIsScrolling) private var listIsScrolling
    @State private var isHovered = false

    public init(
        item: ClipItem, isSelected: Bool = false, previewsHidden: Bool = false,
        shortcutNumber: Int? = nil, thumbnail: Image? = nil,
        selectionNamespace: Namespace.ID? = nil, isSelectionAnchor: Bool = true
    ) {
        self.item = item
        self.isSelected = isSelected
        self.previewsHidden = previewsHidden || ClipSafePresentation.requiresMasking(item)
        self.shortcutNumber = shortcutNumber
        self.thumbnail = thumbnail
        self.selectionNamespace = selectionNamespace
        self.isSelectionAnchor = isSelectionAnchor
    }

    /// Whether a clip is close enough to expiry to earn the row countdown:
    /// within the next hour and not already past. Pure so the threshold is
    /// unit-tested (the view just reads it).
    nonisolated public static func showsExpiryCountdown(
        expiresAt: Date?, now: Date = .now
    ) -> Bool {
        guard let expiresAt else { return false }
        let remaining = expiresAt.timeIntervalSince(now)
        return remaining > 0 && remaining < 3600
    }

    /// The letter a link row's tile shows: the first character of the host,
    /// without a leading `www.`. Parsed locally from the stored preview — no
    /// favicon and no network, so the URL never leaves the device.
    nonisolated public static func linkMonogram(for preview: String) -> String? {
        guard let first = ClipLinkParts(text: preview)?.host.first,
            first.isLetter || first.isNumber
        else { return nil }
        return String(first).uppercased()
    }

    /// Whether a row shows its hover wash. While the list scrolls no row does,
    /// and a row that was under the pointer reads its cleared state once the
    /// list settles, so only the next pointer move lights it again.
    nonisolated public static func hoverState(pointerInside: Bool, listIsScrolling: Bool) -> Bool {
        pointerInside && !listIsScrolling
    }

    /// Row previews are short; the cap guards a malformed oversized one.
    private static let syntaxPreviewLimit = 240

    public var body: some View {
        HStack(spacing: GanchoTokens.Spacing.sm) {
            leadingTile
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if !item.title.isEmpty, !previewsHidden {
                    Text(item.title)
                        .panelFont(.body, .semibold)
                        .lineLimit(1)
                }
                previewText
                    .lineLimit(item.title.isEmpty ? 2 : 1)
                    .foregroundStyle(item.title.isEmpty ? .primary : .secondary)
            }
            Spacer(minLength: GanchoTokens.Spacing.xs)
            trailingMeta
        }
        .padding(.vertical, 7)
        .padding(.horizontal, GanchoTokens.Spacing.xs + 2)
        .background {
            // Scoped to the highlight: an animated selection transaction would
            // also cross-fade the peek and animate the list's scroll-to.
            selectionBackground
                .animation(selectionAnimation, value: isSelected)
                .animation(selectionAnimation, value: isSelectionAnchor)
        }
        .background {
            // Scoped like the highlight above: only the wash animates, never
            // the row's own layout.
            hoverBackground
                .animation(GanchoMotion.quick(reduceMotion: reduceMotion), value: isHovered)
        }
        .onHover {
            isHovered = Self.hoverState(pointerInside: $0, listIsScrolling: listIsScrolling)
        }
        .onChange(of: listIsScrolling) { _, scrolling in
            isHovered = Self.hoverState(pointerInside: isHovered, listIsScrolling: scrolling)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        // Surface the ⌘N quick-paste badge (VoiceOver reads it as the value) and
        // the selection state as a trait — both are otherwise invisible to
        // assistive tech and to UI tests asserting one-row-selected / distinct
        // shortcuts.
        .accessibilityValue(shortcutNumber.map { Text(verbatim: "⌘\($0)") } ?? Text(verbatim: ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("clip-row")
    }

    @ViewBuilder private var previewText: some View {
        if previewsHidden {
            Text(verbatim: "•••").panelFont(.callout)
        } else if item.kind == .code {
            Text(highlightedPreview).panelFont(.callout, design: .monospaced)
        } else {
            Text(ByteSize.humanizedPreview(item.preview))
                .panelFont(item.title.isEmpty ? .body : .callout)
        }
    }

    /// The same local tokenizer the peek and the Library editor use, so a code
    /// row already reads as code in the list.
    private var highlightedPreview: AttributedString {
        GanchoTokens.Syntax.highlighted(String(item.preview.prefix(Self.syntaxPreviewLimit)))
    }

    @ViewBuilder private var hoverBackground: some View {
        if isHovered, !isSelected {
            RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
                .fill(.quaternary.opacity(0.45))
        }
    }

    /// Source · time on top, then the state markers and the ⌘N badge. The pin
    /// marker's scale-in is scoped here so a pin toggle never animates the
    /// row's reflow into the Pinned section.
    private var trailingMeta: some View {
        VStack(alignment: .trailing, spacing: 3) {
            sourceTimeLine
            HStack(spacing: GanchoTokens.Spacing.xxs) {
                if item.expiresAt != nil {
                    // A live "expires in mm:ss" on rows about to age out — sensitive
                    // clips especially get a short lifetime, and the peek only warns
                    // once you open it. The TimelineView re-evaluates the SHOW/HIDE
                    // decision on a coarse tick (the inner Text self-updates every
                    // second on its own), so the badge appears when a clip crosses
                    // into the window and disappears once it expires — without
                    // waiting for an unrelated view update. Rows without an expiry
                    // never mount the timeline.
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        if let expiresAt = item.expiresAt,
                            Self.showsExpiryCountdown(expiresAt: expiresAt, now: context.date)
                        {
                            HStack(spacing: 2) {
                                Image(systemName: "timer")
                                Text(expiresAt, style: .timer)
                            }
                            .panelFont(.caption2, digits: true)
                            .foregroundStyle(GanchoTokens.Palette.warning)
                            .accessibilityLabel(Text("Expires soon"))
                        }
                    }
                }
                if item.tags.contains("universal-clipboard") {
                    Image(systemName: "icloud.and.arrow.down")
                        .panelFont(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("From another device"))
                }
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .panelFont(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("Pinned"))
                        .transition(.scale.combined(with: .opacity))
                }
                if let shortcutNumber {
                    ClipShortcutBadge(number: shortcutNumber)
                }
            }
        }
        .animation(GanchoMotion.quick(reduceMotion: reduceMotion), value: item.isPinned)
    }

    private var selectionAnimation: Animation? {
        selectionNamespace == nil
            ? nil : GanchoMotion.quick(reduceMotion: reduceMotion)
    }

    /// Accent wash plus the design's accent bar on the leading edge. With a
    /// namespace the pair is ONE view shared by every row, so a selection change
    /// moves it rather than swapping it.
    @ViewBuilder private var selectionBackground: some View {
        if isSelected {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
                    .fill(GanchoTokens.Palette.accent.opacity(0.12))
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(GanchoTokens.Palette.accent)
                    .frame(width: 3)
                    .padding(.vertical, GanchoTokens.Spacing.xs)
            }
            .modifier(
                SharedSelectionGeometry(
                    namespace: selectionNamespace, rowID: isSelectionAnchor ? nil : item.id))
        }
    }

    /// Kind-tinted rounded tile (the design's row icon). Links, colours and
    /// images carry their identity in full colour (a host monogram, the real
    /// swatch, the thumbnail); everything else keeps the glyph on a tint wash.
    @ViewBuilder private var leadingTile: some View {
        let tint = GanchoTokens.Palette.kindTint(for: item.kind)
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.card, style: .continuous)
        Group {
            if item.kind == .image, !previewsHidden, let thumbnail {
                thumbnail
                    .resizable()
                    .scaledToFill()
                    .frame(width: tileSize, height: tileSize)
                    .clipShape(shape)
                    .overlay(
                        shape.strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline))
            } else if item.kind == .color, !previewsHidden,
                let color = Color(hexString: item.preview)
            {
                shape.fill(color)
                    .overlay(
                        shape.strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline))
            } else if item.kind == .url, !previewsHidden,
                let monogram = Self.linkMonogram(for: item.preview)
            {
                shape.fill(tint.gradient)
                    .overlay {
                        Text(verbatim: monogram)
                            .panelFont(size: 16, .bold, design: .rounded)
                            .foregroundStyle(.white)
                    }
            } else {
                shape.fill(tint.opacity(0.16))
                    .overlay {
                        Image(systemName: item.kind.symbolName)
                            .panelFont(size: 14, .semibold)
                            .foregroundStyle(tint)
                    }
            }
        }
        .frame(width: tileSize, height: tileSize)
    }

    /// "Safari · 12 minutes ago", hidden in private mode. Minute-granular: it sits
    /// beside the preview, and a per-second timer would resize it every tick.
    @ViewBuilder private var sourceTimeLine: some View {
        if !previewsHidden {
            HStack(spacing: 3) {
                if let bundleID = item.sourceAppBundleID, !bundleID.isEmpty {
                    Text(SourceApp.fallbackName(forBundleID: bundleID))
                    Text(verbatim: "·")
                }
                Text(.currentDate, format: .reference(to: item.createdAt, maxFieldCount: 1))
            }
            .panelFont(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }
    }

    /// VoiceOver: kind + preview (masked previews stay masked here too).
    /// Single interpolated `Text` — concatenating with `+` is deprecated in 26.
    private var accessibilityDescription: Text {
        let base = Text.clipRowDescription(for: item, masked: previewsHidden)
        // The row is ONE combined accessibility element with an explicit label,
        // which supersedes the children's labels — so the countdown badge's own
        // label is never announced. Surface expiry here instead (state, not the
        // exact remaining time: the description is computed at render, so a
        // minute count would read stale).
        guard Self.showsExpiryCountdown(expiresAt: item.expiresAt) else { return base }
        return Text("\(base), \(Text("Expires soon"))")
    }
}

/// The ⌘N quick-paste badge, shared by the list row and the gallery card. Hidden
/// from VoiceOver: the row exposes the number as its accessibility value.
public struct ClipShortcutBadge: View {
    let number: Int

    public init(number: Int) {
        self.number = number
    }

    public var body: some View {
        if (1...9).contains(number) {
            Text(verbatim: "⌘\(number)")
                .panelFont(.caption2, .medium, design: .monospaced)
                .foregroundStyle(.secondary)
                .padding(.horizontal, GanchoTokens.Spacing.xxs)
                .padding(.vertical, 1)
                .background(
                    .quaternary,
                    in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.sm, style: .continuous)
                )
                .accessibilityHidden(true)
        }
    }
}

extension Text {
    /// The row's VoiceOver phrase — kind, then the preview or the mask — so the
    /// list row and the gallery card read identically.
    public static func clipRowDescription(for item: ClipItem, masked: Bool) -> Text {
        let preview = masked ? "•••" : ByteSize.humanizedPreview(item.preview)
        return Text("\(Text(LocalizedStringKey(item.kind.rawValue))), \(preview)")
    }
}

/// Lets a row opt into the shared highlight only when its host has a namespace.
/// Non-anchor rows keep the modifier under their own id, so moving the anchor
/// never swaps a still-selected row's background for a new view.
private struct SharedSelectionGeometry: ViewModifier {
    let namespace: Namespace.ID?
    /// nil for the anchor, which claims the shared id.
    let rowID: UUID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(
                id: rowID.map(AnyHashable.init) ?? AnyHashable("clip-selection"), in: namespace)
        } else {
            content
        }
    }
}

/// Primary action button on a glass surface.
public struct ActionButton: View {
    let titleKey: LocalizedStringKey
    let systemImage: String
    let identifier: String
    let action: () -> Void

    public init(
        _ titleKey: LocalizedStringKey, systemImage: String, identifier: String,
        action: @escaping () -> Void
    ) {
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.identifier = identifier
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label(titleKey, systemImage: systemImage)
                .panelFont(.body, .medium)
                .lineLimit(1)
                .padding(.horizontal, GanchoTokens.Spacing.sm)
                .padding(.vertical, GanchoTokens.Spacing.xxs)
        }
        .buttonStyle(.plain)
        .ganchoSurface(radius: GanchoTokens.Radius.md)
        .accessibilityIdentifier(identifier)
    }
}

/// Search field with the panel's type-to-search contract: focused state is
/// owned by the caller; every keystroke updates the binding immediately.
public struct SearchField: View {
    /// `.card` sits on its own glass surface (a standalone control); `.bare`
    /// is the panel header — larger type, no surface of its own, because a
    /// glass control inside a glass panel reads as nested material.
    public enum Style: Sendable {
        case card, bare
    }

    let promptKey: LocalizedStringKey
    let style: Style
    @Binding var text: String

    public init(_ promptKey: LocalizedStringKey, text: Binding<String>, style: Style = .card) {
        self.promptKey = promptKey
        self._text = text
        self.style = style
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
            TextField(promptKey, text: $text)
                .textFieldStyle(.plain)
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
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear search"))
                .accessibilityIdentifier("search-clear")
            }
        }
    }
}
