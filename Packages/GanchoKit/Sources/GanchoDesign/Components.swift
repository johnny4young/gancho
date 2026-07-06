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
        if reduceTransparency || contrast == .increased {
            content.background(.background.secondary, in: shape)
        } else {
            content.glassEffect(.regular, in: shape)
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
    let kind: ClipContentKind

    public init(kind: ClipContentKind) {
        self.kind = kind
    }

    public var body: some View {
        Label(LocalizedStringKey(kind.rawValue), systemImage: kind.symbolName)
            .font(.caption2.weight(.medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("type-badge")
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

    private static func kindRGB(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}

/// One clip row/card: badge, preview (masked kinds render their stored
/// masked preview — the secret never reaches this view), optional thumbnail.
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

    public init(
        item: ClipItem, isSelected: Bool = false, previewsHidden: Bool = false,
        shortcutNumber: Int? = nil, thumbnail: Image? = nil
    ) {
        self.item = item
        self.isSelected = isSelected
        self.previewsHidden = previewsHidden
        self.shortcutNumber = shortcutNumber
        self.thumbnail = thumbnail
    }

    public var body: some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            leadingTile
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                if !item.title.isEmpty, !previewsHidden {
                    Text(item.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                }
                Text(previewsHidden ? "•••" : ByteSize.humanizedPreview(item.preview))
                    .font(item.kind == .code ? .body.monospaced() : .body)
                    .lineLimit(item.title.isEmpty ? 2 : 1)
                    .foregroundStyle(item.title.isEmpty ? .primary : .secondary)
                sourceTimeLine
            }
            Spacer(minLength: 0)
            if item.tags.contains("universal-clipboard") {
                Image(systemName: "icloud.and.arrow.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("From another device"))
            }
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Pinned"))
            }
            if let shortcutNumber, (1...9).contains(shortcutNumber) {
                Text(verbatim: "⌘\(shortcutNumber)")
                    .font(.caption2.weight(.medium).monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, GanchoTokens.Spacing.xxs)
                    .padding(.vertical, 1)
                    .background(
                        .quaternary,
                        in: RoundedRectangle(
                            cornerRadius: GanchoTokens.Radius.sm, style: .continuous)
                    )
                    .accessibilityHidden(true)
            }
        }
        .padding(GanchoTokens.Spacing.xs)
        .background(
            isSelected
                ? AnyShapeStyle(GanchoTokens.Palette.accent.opacity(0.14))
                : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.sm, style: .continuous)
        )
        .overlay(alignment: .leading) {
            // The design marks the selected row with a green accent bar.
            if isSelected {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(GanchoTokens.Palette.accent)
                    .frame(width: 3)
                    .padding(.vertical, GanchoTokens.Spacing.xxs)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityIdentifier("clip-row")
    }

    /// Kind-tinted rounded tile (the design's row icon): a real colour swatch
    /// for colour clips, otherwise the kind glyph on a tint-washed background.
    @ViewBuilder private var leadingTile: some View {
        let tint = GanchoTokens.Palette.kindTint(for: item.kind)
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.sm, style: .continuous)
        if item.kind == .image, !previewsHidden, let thumbnail {
            thumbnail
                .resizable()
                .scaledToFill()
                .frame(width: 30, height: 30)
                .clipShape(shape)
                .overlay(shape.strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline))
        } else {
            shape
                .fill(tileFill(tint))
                .frame(width: 30, height: 30)
                .overlay {
                    if !(item.kind == .color && !previewsHidden) {
                        Image(systemName: item.kind.symbolName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                }
        }
    }

    private func tileFill(_ tint: Color) -> AnyShapeStyle {
        if item.kind == .color, !previewsHidden, let color = Color(hexString: item.preview) {
            return AnyShapeStyle(color)
        }
        return AnyShapeStyle(tint.opacity(0.18))
    }

    /// "Safari · 12 min" — source app (cheap, NSWorkspace-free fallback name)
    /// and the relative capture time. Hidden in private mode.
    @ViewBuilder private var sourceTimeLine: some View {
        if !previewsHidden {
            HStack(spacing: 3) {
                if let bundleID = item.sourceAppBundleID, !bundleID.isEmpty {
                    Text(SourceApp.fallbackName(forBundleID: bundleID))
                    Text(verbatim: "·")
                }
                Text(item.createdAt, style: .relative)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }
    }

    /// VoiceOver: kind + preview (masked previews stay masked here too).
    /// Single interpolated `Text` — concatenating with `+` is deprecated in 26.
    private var accessibilityDescription: Text {
        let preview = previewsHidden ? "•••" : ByteSize.humanizedPreview(item.preview)
        return Text("\(Text(LocalizedStringKey(item.kind.rawValue))), \(preview)")
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
                .font(.body.weight(.medium))
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
    let promptKey: LocalizedStringKey
    @Binding var text: String

    public init(_ promptKey: LocalizedStringKey, text: Binding<String>) {
        self.promptKey = promptKey
        self._text = text
    }

    public var body: some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .center)
                .accessibilityHidden(true)
            TextField(promptKey, text: $text)
                .textFieldStyle(.plain)
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
        .padding(GanchoTokens.Spacing.xs)
        .ganchoSurface(radius: GanchoTokens.Radius.md)
    }
}
