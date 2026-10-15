import SwiftUI

/// Compact icon actions keep one label for help and accessibility, with a
/// hit area that scales alongside the panel's text instead of the glyph alone.
public struct IconActionButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let identifier: String
    let role: ButtonRole?
    let action: () -> Void
    @Environment(\.panelTypeScale) private var typeScale

    public init(
        _ title: LocalizedStringKey, systemImage: String, identifier: String,
        role: ButtonRole? = nil, action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.identifier = identifier
        self.role = role
        self.action = action
    }

    public var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .panelFont(.callout)
                .frame(minWidth: targetSize, minHeight: targetSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(Text(title))
        .accessibilityIdentifier(identifier)
    }

    private var targetSize: CGFloat {
        #if os(macOS)
            28 * typeScale
        #else
            44
        #endif
    }
}
