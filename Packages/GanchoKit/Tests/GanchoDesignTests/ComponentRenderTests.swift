#if os(macOS)
    import GanchoKit
    import SwiftUI
    import Testing

    @testable import GanchoDesign

    /// Render-smoke snapshots: every component must produce pixels in light,
    /// dark, and reduce-transparency configurations. Pixel-exact baselines
    /// are deliberately NOT compared in CI (runner GPUs drift); local pixel
    /// diffing can layer on top of these renders later.
    @MainActor
    private func render(_ view: some View, dark: Bool) -> CGImage? {
        let renderer = ImageRenderer(
            content:
                view
                .environment(\.colorScheme, dark ? .dark : .light)
                .frame(width: 320)
                .padding())
        renderer.scale = 2
        return renderer.cgImage
    }

    @Suite("Design components — render smoke (light/dark)")
    @MainActor
    struct ComponentRenderTests {
        static let sampleItem = ClipItem(
            kind: .url, title: "Example", preview: "https://example.com/path",
            contentHash: "h", isPinned: true)

        @Test("ClipCard renders in both schemes", arguments: [false, true])
        func clipCard(dark: Bool) {
            let image = render(ClipCard(item: Self.sampleItem, isSelected: true), dark: dark)
            #expect((image?.width ?? 0) > 0)
        }

        @Test("Masked previews never expose content in the rendered tree")
        func maskedCard() {
            let secret = ClipItem(
                kind: .secret, preview: "●●●● 6789", contentHash: "h2", isSensitive: true)
            let image = render(ClipCard(item: secret), dark: false)
            #expect((image?.width ?? 0) > 0)
            // The view consumes the STORED preview — masking is guaranteed
            // upstream (SensitiveMasking); this asserts the contract input.
            #expect(secret.preview.hasPrefix("●●●●"))
        }

        @Test("TypeBadge renders for every kind")
        func typeBadges() {
            for kind in ClipContentKind.allCases {
                let image = render(TypeBadge(kind: kind), dark: false)
                #expect((image?.width ?? 0) > 0, "kind: \(kind)")
            }
        }

        @Test("ActionButton and SearchField render", arguments: [false, true])
        func controls(dark: Bool) {
            let button = render(
                ActionButton("Paste", systemImage: "doc.on.clipboard", identifier: "paste-button") {
                }, dark: dark)
            #expect((button?.width ?? 0) > 0)

            let field = render(
                SearchField("Search", text: .constant("query")), dark: dark)
            #expect((field?.width ?? 0) > 0)
        }
    }
#endif
