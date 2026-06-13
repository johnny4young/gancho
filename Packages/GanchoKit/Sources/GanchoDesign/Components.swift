import GanchoKit
import SwiftUI

/// Glass surface treatment shared by every component: Liquid Glass when the
/// user allows transparency, a solid readable surface when they don't.
/// Glass-native is a day-1 commitment (the opt-out dies with SDK 27) — the
/// fallback exists for ACCESSIBILITY, not for a legacy look.
public struct GanchoSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let shape: RoundedRectangle

    public func body(content: Content) -> some View {
        if reduceTransparency {
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

/// One clip row/card: badge, preview (masked kinds render their stored
/// masked preview — the secret never reaches this view), optional thumbnail.
public struct ClipCard: View {
    let item: ClipItem
    let isSelected: Bool

    public init(item: ClipItem, isSelected: Bool = false) {
        self.item = item
        self.isSelected = isSelected
    }

    public var body: some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            Image(systemName: item.kind.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: GanchoTokens.Spacing.lg)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xxs) {
                if !item.title.isEmpty {
                    Text(item.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                }
                Text(item.preview)
                    .font(item.kind == .code ? .body.monospaced() : .body)
                    .lineLimit(2)
                    .foregroundStyle(item.title.isEmpty ? .primary : .secondary)
            }
            Spacer(minLength: 0)
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Pinned"))
            }
        }
        .padding(GanchoTokens.Spacing.xs)
        .background(
            isSelected ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.sm, style: .continuous)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityIdentifier("clip-row")
    }

    /// VoiceOver: kind + preview (masked previews stay masked here too).
    private var accessibilityDescription: Text {
        Text(LocalizedStringKey(item.kind.rawValue)) + Text(", ") + Text(item.preview)
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
        HStack(spacing: GanchoTokens.Spacing.xxs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(promptKey, text: $text)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("search-field")
        }
        .padding(GanchoTokens.Spacing.xs)
        .ganchoSurface(radius: GanchoTokens.Radius.md)
    }
}
