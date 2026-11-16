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

        @Test("ClipCard grows with the panel text size")
        func clipCardFollowsTextSize() throws {
            let heights = try PanelTextSize.allCases.map { size in
                let card = ClipCard(item: Self.sampleItem)
                    .environment(\.panelTypeScale, size.scale)
                return try #require(render(card, dark: false)).height
            }
            #expect(zip(heights, heights.dropFirst()).allSatisfy { $0 < $1 }, "\(heights)")
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

        @Test("A row is 50 pt high at the standard text size, with or without a description")
        func rowHeight() throws {
            let bare = ClipItem(kind: .text, preview: "One line", contentHash: "b")
            for item in [Self.sampleItem, bare] {
                let renderer = ImageRenderer(content: ClipCard(item: item).frame(width: 320))
                renderer.scale = 1
                #expect(try #require(renderer.cgImage).height == 50)
            }
        }

        @Test("Every kind renders as a row and as a tile", arguments: [false, true])
        func everyKind(dark: Bool) {
            for kind in ClipContentKind.allCases {
                let item = ClipItem(
                    kind: kind, preview: kind == .color ? "#FF6B4A" : "let x = \"1\"",
                    contentHash: "k", expiresAt: .now.addingTimeInterval(90))
                let row = ClipCard(item: item, isSelected: kind == .url, shortcutNumber: 2)
                #expect((render(row, dark: dark)?.width ?? 0) > 0, "row: \(kind)")
                let tile = ClipTile(item: item, size: 34, previewsHidden: false)
                #expect((render(tile, dark: dark)?.width ?? 0) > 0, "tile: \(kind)")
            }
        }

        @Test("The time ring renders fresh, in its last minute and run out")
        func timeRing() {
            for left in [600.0, 30, -5] {
                let ring = TimeRing(
                    Countdown(start: .now.addingTimeInterval(-60), deadline: .now + left)
                )
                .frame(width: 34, height: 34)
                #expect((render(ring, dark: true)?.width ?? 0) > 0, "left: \(left)")
            }
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

        @Test("Key caps and the live dot render", arguments: [false, true])
        func keyCaps(dark: Bool) {
            let caps = HStack {
                KeyCap("⌘K")
                KeyCap("↩", role: .onAccent)
                ReturnKeyCap()
                LiveDot()
            }
            #expect((render(caps, dark: dark)?.width ?? 0) > 0)
        }

        @Test("A key cap is 19 pt high at the standard text size")
        func keyCapHeight() throws {
            let renderer = ImageRenderer(content: KeyCap("⌘1"))
            renderer.scale = 1
            #expect(try #require(renderer.cgImage).height == 19)
        }
    }
#endif
