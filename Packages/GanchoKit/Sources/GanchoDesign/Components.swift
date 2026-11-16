import GanchoKit
import SwiftUI

/// Glass surface treatment shared by every component: Liquid Glass when the
/// user allows transparency, a solid readable surface when they don't.
/// Glass-native is a day-1 commitment (the opt-out dies with SDK 27) — the
/// fallback exists for ACCESSIBILITY, not for a legacy look.
public struct GanchoSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.ganchoOpaqueSurfaces) private var opaqueSurfaces

    let shape: RoundedRectangle
    var level: GanchoTokens.SurfaceLevel = .card

    public func body(content: Content) -> some View {
        // Increased contrast ALSO opts out of glass: translucency is the
        // main legibility cost, regardless of which setting flagged it.
        if !opaqueSurfaces, !reduceTransparency, contrast != .increased {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(GanchoTokens.Palette.surface(level), in: shape)
        }
    }
}

extension EnvironmentValues {
    /// Solid surfaces instead of glass, for windows the user keeps opaque.
    @Entry public var ganchoOpaqueSurfaces = false
}

extension View {
    /// Standard Gancho glass card surface; `level` picks the opaque fallback.
    public func ganchoSurface(
        radius: CGFloat = GanchoTokens.Radius.card,
        level: GanchoTokens.SurfaceLevel = .card
    ) -> some View {
        modifier(
            GanchoSurface(
                shape: RoundedRectangle(cornerRadius: radius, style: .continuous), level: level))
    }

    /// One of the four shadow steps. Dark appearance casts no shadow and gets
    /// a 1 pt top highlight instead, so raised layers still separate.
    public func ganchoElevation(
        _ elevation: GanchoTokens.Elevation, cornerRadius: CGFloat = GanchoTokens.Radius.md
    ) -> some View {
        modifier(ElevationModifier(elevation: elevation, cornerRadius: cornerRadius))
    }
}

private struct ElevationModifier: ViewModifier {
    let elevation: GanchoTokens.Elevation
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content.overlay {
                if elevation != .flat {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.12), .clear], startPoint: .top,
                                endPoint: .center),
                            lineWidth: GanchoTokens.Stroke.hairline)
                }
            }
        } else {
            content.shadow(
                color: .black.opacity(elevation.opacity), radius: elevation.radius, y: elevation.y)
        }
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

    nonisolated static let washOpacity = 0.14

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
                .panelFont(.subheadline, .semibold)
                .padding(.horizontal, GanchoTokens.Spacing.xs)
                .padding(.vertical, 3)
                .ganchoTintedPill(tint, wash: Self.washOpacity)
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
    /// The path and query with percent escapes decoded, or nil when decoding
    /// changes nothing (the URL line already says it).
    public let decoded: String?
    /// What follows the host (path and query, decoded when that reads better);
    /// nil for a bare host, so a card never repeats the host it already shows.
    public let path: String?
    /// "https", "mailto"… lowercased, for the link's insight chip.
    public let scheme: String?

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
        let components = URLComponents(string: trimmed)
        let raw =
            (components?.percentEncodedPath ?? "")
            + (components?.percentEncodedQuery.map { "?\($0)" } ?? "")
        let readable = raw.removingPercentEncoding
        decoded = readable == raw ? nil : readable
        let shown = readable ?? raw
        path = shown.isEmpty || shown == "/" ? nil : shown
        scheme = url.scheme?.lowercased()
    }

    /// `[title](url)`, titled by the clip or else by its host. Brackets in the
    /// title and parentheses in the URL are escaped so the link stays one link.
    public func markdownLink(title: String) -> String {
        let label = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let escapedLabel = (label.isEmpty ? host : label)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
        let escapedURL =
            text
            .replacingOccurrences(of: "(", with: "%28")
            .replacingOccurrences(of: ")", with: "%29")
            .replacingOccurrences(of: " ", with: "%20")
        return "[\(escapedLabel)](\(escapedURL))"
    }
}

extension GanchoTokens.Palette {
    /// Clip-kind family colours: the tint
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

/// One clip row: its tile, the content in its native form over a quiet
/// description (`ClipRowContent`), and a trailing meta column (source · time,
/// markers, key cap). A protected clip shows its stored mask, never its content.
public struct ClipCard: View {
    let item: ClipItem
    let isSelected: Bool
    /// A protected clip or Private Mode: the VoiceOver label masks on it.
    let previewsHidden: Bool
    let masking: ClipRowContent.Masking
    let content: ClipRowContent
    /// A protected clip's lifetime; nil without an expiry and in Private Mode.
    let countdown: Countdown?
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
    /// The current lifetime setting, which caps a stored expiry.
    let sensitiveLifetime: TimeInterval?
    /// A clip copied on another device names that device; nil leaves rows as they were.
    let foreignDevice: String?
    // Dynamic Type grows the tile on iOS; the panel's own scale on the Mac.
    @ScaledMetric(relativeTo: .body) private var baseTileSize: CGFloat = 34
    @Environment(\.panelTypeScale) private var typeScale
    private var tileSize: CGFloat { baseTileSize * typeScale }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.listIsScrolling) private var listIsScrolling
    @State private var isHovered = false

    public init(
        item: ClipItem, isSelected: Bool = false, previewsHidden: Bool = false,
        shortcutNumber: Int? = nil, thumbnail: Image? = nil,
        selectionNamespace: Namespace.ID? = nil, isSelectionAnchor: Bool = true,
        currentDeviceName: String? = nil, sensitiveLifetime: TimeInterval? = nil
    ) {
        let protected = ClipSafePresentation.requiresMasking(item)
        let masking = ClipRowContent.Masking.for(item, previewsHidden: previewsHidden)
        self.item = item
        self.isSelected = isSelected
        self.previewsHidden = previewsHidden || protected
        self.masking = masking
        self.content = ClipRowContent(item: item, masking: masking)
        self.countdown =
            masking == .storedMask ? Countdown(item: item, lifetime: sensitiveLifetime) : nil
        self.shortcutNumber = shortcutNumber
        self.thumbnail = thumbnail
        self.selectionNamespace = selectionNamespace
        self.isSelectionAnchor = isSelectionAnchor
        self.sensitiveLifetime = sensitiveLifetime
        // Hidden previews hide where a clip came from too, in the label as well.
        self.foreignDevice =
            previewsHidden
            ? nil : currentDeviceName.flatMap { Self.foreignDeviceName(of: item, current: $0) }
    }

    /// The device a clip came from, when that is not this one. Nil for a clip
    /// with no recorded device, so older and local clips stay unlabelled.
    nonisolated public static func foreignDeviceName(
        of item: ClipItem, current: String
    )
        -> String?
    {
        guard
            let device = item.sourceDeviceName?.trimmingCharacters(in: .whitespacesAndNewlines),
            !device.isEmpty,
            device != current.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        return device
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
            VStack(alignment: .leading, spacing: 3) {
                headline
                    .lineLimit(1)
                    .foregroundStyle(GanchoTokens.Palette.ink)
                description
            }
            Spacer(minLength: GanchoTokens.Spacing.xs)
            trailingMeta
        }
        // With the tile, a row is 50 pt at the standard text size.
        .padding(.vertical, GanchoTokens.Spacing.xs)
        .padding(.horizontal, GanchoTokens.Spacing.xs + 1)
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

    /// Line 1: the clip as itself.
    @ViewBuilder private var headline: some View {
        switch content.headline {
        case .text(let text):
            Text(verbatim: text).panelFont(.body, .medium)
        case .kindName(let kind):
            Text(kind.cardName).panelFont(.body, .medium)
        case .value(let value):
            Text(verbatim: value).panelFont(.callout, design: .monospaced)
        case .code(let line):
            Text(GanchoTokens.Syntax.tonal(String(line.prefix(Self.syntaxPreviewLimit))))
                .panelFont(.callout, design: .monospaced)
        case .link(let host, let path):
            let rest = Text(verbatim: path ?? "").foregroundStyle(GanchoTokens.Palette.ink3)
            Text("\(Text(verbatim: host).fontWeight(.semibold))\(rest)")
                .panelFont(.body, .medium)
                .truncationMode(.middle)
        }
    }

    /// Line 2: what the clip is, and for a protected clip the time it has left.
    @ViewBuilder private var description: some View {
        if let countdown {
            // Ticks with the ring; rows without a lifetime never mount a timeline.
            TimelineView(.periodic(from: countdown.deadline, by: 1)) { context in
                descriptionLine(
                    timeLeft: countdown.isRunning(at: context.date)
                        ? countdown.clock(at: context.date) : nil)
            }
        } else if !content.details.isEmpty {
            descriptionLine(timeLeft: nil)
        }
    }

    private func descriptionLine(timeLeft: String?) -> some View {
        let parts =
            content.details.map(Self.text(for:)) + (timeLeft.map { [Text("\($0) left")] } ?? [])
        let line = parts.dropFirst().reduce(parts.first ?? Text(verbatim: "")) {
            Text("\($0) · \($1)")
        }
        return
            line
            .panelFont(.subheadline, digits: true)
            .foregroundStyle(GanchoTokens.Palette.ink3)
            .lineLimit(1)
    }

    private static func text(for detail: ClipRowContent.Detail) -> Text {
        switch detail {
        case .verbatim(let text): Text(verbatim: text)
        case .lines(let count): Text("\(count) lines")
        case .kindName(let kind): Text(kind.cardName)
        }
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
            if let foreignDevice {
                // Its own line: a full device name beside the app and age left
                // all three truncated.
                HStack(spacing: 3) {
                    Image(systemName: "desktopcomputer")
                    Text(verbatim: foreignDevice).lineLimit(1).truncationMode(.middle)
                }
                .panelFont(.caption2)
                .foregroundStyle(GanchoTokens.Palette.ink3)
                .frame(maxWidth: 140, alignment: .trailing)
                .accessibilityHidden(true)
            }
            HStack(spacing: GanchoTokens.Spacing.xxs) {
                // The description already counts a protected clip down.
                if item.expiresAt != nil, countdown == nil {
                    // A coarse tick decides show/hide (the timer text updates
                    // itself), so the badge appears as a clip enters its last
                    // hour and goes once it expires.
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        if let expiresAt = item.expiresAt,
                            Self.showsExpiryCountdown(expiresAt: expiresAt, now: context.date)
                        {
                            expiryBadge(expiresAt)
                        }
                    }
                }
                // The device name already says where it came from.
                if item.tags.contains("universal-clipboard"), foreignDevice == nil {
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
                // Return pastes only the anchor of a ⇧ range.
                ClipShortcutBadge(
                    number: shortcutNumber, isSelected: isSelected && isSelectionAnchor)
            }
        }
        .animation(GanchoMotion.quick(reduceMotion: reduceMotion), value: item.isPinned)
    }

    private func expiryBadge(_ expiresAt: Date) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "timer")
            Text(expiresAt, style: .timer)
        }
        .panelFont(.caption2, digits: true)
        .accessibilityLabel(Text("Expires soon"))
        .foregroundStyle(GanchoTokens.Palette.warningInk)
    }

    private var selectionAnimation: Animation? {
        selectionNamespace == nil
            ? nil : GanchoMotion.quick(reduceMotion: reduceMotion)
    }

    /// A neutral wash, never a leading bar or a ring. With a namespace it is
    /// ONE view shared by every row, so a selection change moves it rather
    /// than swapping it.
    @ViewBuilder private var selectionBackground: some View {
        if isSelected {
            let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
            shape
                .fill(GanchoTokens.Palette.selectionWash)
                .modifier(
                    SharedSelectionGeometry(
                        namespace: selectionNamespace, rowID: isSelectionAnchor ? nil : item.id))
        }
    }

    private var leadingTile: some View {
        ClipTile(
            item: item, size: tileSize, previewsHidden: masking == .hidden, thumbnail: thumbnail,
            sensitiveLifetime: sensitiveLifetime)
    }

    /// "Safari · 12 minutes ago", hidden in private mode. Minute-granular: it sits
    /// beside the preview, and a per-second timer would resize it every tick.
    @ViewBuilder private var sourceTimeLine: some View {
        if masking != .hidden {
            HStack(spacing: 3) {
                if let bundleID = item.sourceAppBundleID, !bundleID.isEmpty {
                    Text(SourceApp.fallbackName(forBundleID: bundleID))
                    Text(verbatim: "·")
                }
                Text(.currentDate, format: .reference(to: item.createdAt, maxFieldCount: 1))
            }
            .panelFont(.caption2)
            .foregroundStyle(GanchoTokens.Palette.ink3)
            .lineLimit(1)
        }
    }

    /// VoiceOver: kind + preview (masked previews stay masked here too).
    /// Single interpolated `Text` — concatenating with `+` is deprecated in 26.
    private var accessibilityDescription: Text {
        let described = Text.clipRowDescription(for: item, masked: previewsHidden)
        let base = foreignDevice.map { Text("\(described), from \($0)") } ?? described
        // The row is ONE combined accessibility element with an explicit label,
        // which supersedes the children's labels — so the countdown badge's own
        // label is never announced. Surface expiry here instead (state, not the
        // exact remaining time: the description is computed at render, so a
        // minute count would read stale).
        guard Self.showsExpiryCountdown(expiresAt: item.expiresAt) else { return base }
        return Text("\(base), \(Text("Expires soon"))")
    }
}

/// A row's key: ⌘N for the first nine, and the Return cap in its place on the
/// selected row. Hidden from VoiceOver: the row exposes the number as its
/// accessibility value and selection as a trait.
public struct ClipShortcutBadge: View {
    public enum Key: Equatable, Sendable {
        case returnKey
        case number(Int)
    }

    let key: Key?

    public init(number: Int?, isSelected: Bool = false) {
        key = Self.key(number: number, isSelected: isSelected)
    }

    /// Return on the selected row, numbered or not; ⌘1–⌘9 elsewhere.
    nonisolated public static func key(number: Int?, isSelected: Bool) -> Key? {
        if isSelected { return .returnKey }
        return number.flatMap { (1...9).contains($0) ? .number($0) : nil }
    }

    public var body: some View {
        switch key {
        case .returnKey: ReturnKeyCap()
        case .number(let number): KeyCap("⌘\(number)").accessibilityHidden(true)
        case nil: EmptyView()
        }
    }
}

extension Text {
    /// The row's VoiceOver phrase — kind, then the preview or the mask — so the
    /// list row and the gallery card read identically.
    public static func clipRowDescription(for item: ClipItem, masked: Bool) -> Text {
        let preview =
            masked
            ? "•••"
            : item.imageInfo?.rowDetail(titled: false) ?? ByteSize.humanizedPreview(item.preview)
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
