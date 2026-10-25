#if canImport(AppKit)
    import AppKit
    import GanchoKit
    import SwiftUI
    import Testing

    @testable import GanchoDesign

    @Suite("Menu-bar glyph — a template hook and one coloured badge")
    @MainActor
    struct MenuBarGlyphTests {
        nonisolated static let badges: [MenuBarBadge] = [
            .denied, .paused, .privateMode, .ignoreNext, .stack(3)
        ]

        private struct RGBA {
            let red, green, blue, alpha: Int
        }

        /// RGBA at a point (y-up, in points) of `image` drawn at 4×.
        private func pixel(_ image: NSImage, at point: NSPoint) -> RGBA {
            let scale: CGFloat = 4
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * scale),
                pixelsHigh: Int(image.size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                bitsPerPixel: 0)!
            rep.size = image.size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            image.draw(in: NSRect(origin: .zero, size: image.size))
            NSGraphicsContext.restoreGraphicsState()
            let color = rep.colorAt(
                x: Int(point.x * scale), y: rep.pixelsHigh - 1 - Int(point.y * scale))!
                .usingColorSpace(.sRGB)!
            return RGBA(
                red: Int((color.redComponent * 255).rounded()),
                green: Int((color.greenComponent * 255).rounded()),
                blue: Int((color.blueComponent * 255).rounded()),
                alpha: Int((color.alphaComponent * 255).rounded()))
        }

        private func resolved(_ color: NSColor) -> Color.Resolved {
            let srgb = color.usingColorSpace(.sRGB)!
            return Color.Resolved(
                colorSpace: .sRGB, red: Float(srgb.redComponent), green: Float(srgb.greenComponent),
                blue: Float(srgb.blueComponent))
        }

        @Test("Every badge glyph reads at 4.5:1 or more on its fill", arguments: badges)
        func glyphContrast(badge: MenuBarBadge) {
            let ratio = Contrast.ratio(
                resolved(MenuBarGlyph.glyphColor(for: badge)),
                resolved(MenuBarGlyph.fill(for: badge)))
            #expect(ratio >= Contrast.text, "\(badge): \(ratio)")
        }

        @Test("Badge fills match the panel's state colours")
        func fillsMatchTokens() {
            var light = EnvironmentValues()
            light.colorScheme = .light
            let pairs: [(MenuBarBadge, Color)] = [
                (.paused, GanchoTokens.Palette.warning),
                (.privateMode, GanchoTokens.Palette.indigo),
                (.denied, GanchoTokens.Palette.danger)
            ]
            for (badge, token) in pairs {
                #expect(
                    resolved(MenuBarGlyph.fill(for: badge)).description
                        == token.resolve(in: light).description, "\(badge)")
            }
        }

        @Test("The hook stays a template; a badge notches it and paints its own colour")
        func render() {
            let plain = MenuBarGlyph.hookImage(badged: false)
            let badged = MenuBarGlyph.hookImage(badged: true)
            #expect(plain.isTemplate && badged.isTemplate)
            #expect(pixel(plain, at: NSPoint(x: 9.4, y: 9.4)).alpha > 200, "the stem is drawn")
            #expect(pixel(badged, at: MenuBarGlyph.badgeCenter).alpha == 0, "the notch is clear")
            #expect(
                pixel(badged, at: NSPoint(x: 10.6, y: 4.9)).alpha > 200,
                "the curl stays whole beside it")

            let badge = MenuBarGlyph.badgeImage(.privateMode)
            #expect(!badge.isTemplate)
            let fill = pixel(badge, at: NSPoint(x: 2.5, y: 6))
            #expect(fill.red == 0x5E && fill.green == 0x5C && fill.blue == 0xE6, "\(fill)")
            let ring = pixel(badge, at: NSPoint(x: 0.4, y: 6))
            #expect(ring.red > 240 && ring.green > 240 && ring.blue > 240, "white ring \(ring)")
        }

        @Test("The badge follows the status button as it resizes, and hides with no state")
        func badgeFollowsTheButton() throws {
            let offset = MenuBarGlyph.badgeCenter.x - MenuBarGlyph.badgedWidth / 2
            let button = NSButton(frame: NSRect(x: 0, y: 0, width: 30, height: 22))
            MenuBarGlyph.apply(badge: .paused, to: button)
            button.layoutSubtreeIfNeeded()
            let badge = try #require(button.subviews.compactMap { $0 as? MenuBarBadgeView }.first)
            #expect(abs(badge.frame.midX - (15 + offset)) < 0.01)
            // Below the hook's centre, as the badged image draws it.
            let below = MenuBarGlyph.hookSide / 2 - MenuBarGlyph.badgeCenter.y
            let expectedY = button.isFlipped ? 11 + below : 11 - below
            #expect(abs(badge.frame.midY - expectedY) < 0.01, "\(badge.frame)")
            button.setFrameSize(NSSize(width: 40, height: 22))
            button.layoutSubtreeIfNeeded()
            #expect(abs(badge.frame.midX - (20 + offset)) < 0.01, "moved with the wider button")
            MenuBarGlyph.apply(badge: nil, to: button)
            #expect(badge.isHidden)
            #expect(button.subviews.count { $0 is MenuBarBadgeView } == 1, "one badge view, reused")
        }
    }
#endif
