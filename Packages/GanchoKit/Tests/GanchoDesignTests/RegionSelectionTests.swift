#if canImport(AppKit)
    import AppKit
    import Synchronization
    import Testing

    @testable import GanchoDesign

    @Suite("Nonactivating region selection")
    @MainActor struct RegionSelectionTests {
        @Test func tracksMotionEvenWhenAnotherApplicationIsActive() {
            let view = makeView()
            view.updateTrackingAreas()
            let options = view.trackingAreas.first?.options
            #expect(options?.contains(.activeAlways) == true)
            #expect(options?.contains(.mouseMoved) == true)
            #expect(options?.contains(.mouseEnteredAndExited) == true)
            #expect(options?.contains(.enabledDuringMouseDrag) == true)
            #expect(options?.contains(.inVisibleRect) == true)
            #expect(options?.contains(.cursorUpdate) == false)
        }

        @Test func layoutDoesNotAccumulateTrackingAreas() {
            let view = makeView()
            for _ in 0..<20 { view.updateTrackingAreas() }
            #expect(view.trackingAreas.count == 1)
        }

        @Test func entryMotionAndDragKeepTheSelectionCursor() throws {
            let cursor = RecordingCursor(
                image: NSImage(size: NSSize(width: 16, height: 16)), hotSpot: .zero)
            let view = makeView(cursor: cursor)
            let motion = try #require(
                NSEvent.mouseEvent(
                    with: .mouseMoved, location: NSPoint(x: 10, y: 10), modifierFlags: [],
                    timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                    clickCount: 0, pressure: 0))
            view.mouseEntered(with: motion)
            view.mouseMoved(with: motion)
            view.mouseDown(with: motion)
            view.mouseDragged(with: motion)
            #expect(cursor.updates == 4)
            #expect(view.acceptsFirstMouse(for: motion))
            #expect(view.needsPanelToBecomeKey)
            #expect(view.acceptsFirstResponder)
        }

        @Test func aClosedSelectionCannotRestoreItsCursorFromQueuedEvents() throws {
            let cursor = RecordingCursor(
                image: NSImage(size: NSSize(width: 16, height: 16)), hotSpot: .zero)
            let view = makeView(cursor: cursor)
            view.updateTrackingAreas()
            view.endSelection()
            view.endSelection()
            view.updateTrackingAreas()
            let motion = try #require(
                NSEvent.mouseEvent(
                    with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
            view.mouseEntered(with: motion)
            view.mouseMoved(with: motion)
            view.mouseDown(with: motion)
            view.mouseDragged(with: motion)
            #expect(cursor.updates == 0)
            #expect(view.trackingAreas.isEmpty)
        }

        @Test func cursorHotSpotIsTheFusedCrosshairIntersection() {
            let cursor = RegionSelectionCursor.make()
            #expect(cursor.hotSpot == NSPoint(x: 16, y: 14))
            #expect(cursor.image.size == NSSize(width: 32, height: 36))
            #expect(!cursor.image.isTemplate)
        }

        @Test(arguments: [1, 2, 3], [false, true])
        func fusedCursorKeepsItsHotSpotAndOpenHookAtDifferentScales(scale: Int, dark: Bool) throws {
            let bitmap = try renderCursor(scale: scale, dark: dark)
            for point in [NSPoint(x: 16, y: 14), NSPoint(x: 7, y: 14), NSPoint(x: 25, y: 14)] {
                let color = try color(in: bitmap, at: point, scale: scale)
                #expect(color.alphaComponent > 0.9)
                #expect(color.greenComponent > color.redComponent)
                #expect(color.greenComponent > color.blueComponent)
            }
            // Keep the curl open, the old badge area empty, and air above the barb.
            for point in [NSPoint(x: 13, y: 27), NSPoint(x: 25, y: 26), NSPoint(x: 8, y: 17)] {
                #expect(try color(in: bitmap, at: point, scale: scale).alphaComponent < 0.1)
            }
            #expect(
                try color(in: bitmap, at: NSPoint(x: 13, y: 31), scale: scale).alphaComponent > 0.9)
        }

        @Test func fusedCursorHasBothLightAndDarkOutlines() throws {
            let bitmap = try renderCursor(scale: 3)
            var hasWhite = false
            var hasDark = false
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                    guard color.alphaComponent > 0.9 else { continue }
                    hasWhite =
                        hasWhite
                        || min(color.redComponent, color.greenComponent, color.blueComponent) > 0.9
                    hasDark =
                        hasDark
                        || max(color.redComponent, color.greenComponent, color.blueComponent) < 0.2
                }
            }
            #expect(hasWhite)
            #expect(hasDark)
        }

        @Test(arguments: [false, true])
        func cursorUsesItsDeeperGreenInEitherAppAppearance(dark: Bool) throws {
            let bitmap = try renderCursor(scale: 3, dark: dark)
            let pixel = try color(in: bitmap, at: NSPoint(x: 16, y: 14), scale: 3)
            #expect(abs(pixel.redComponent - 0x2E / 255) < 2 / 255)
            #expect(abs(pixel.greenComponent - 0xAD / 255) < 2 / 255)
            #expect(abs(pixel.blueComponent - 0x50 / 255) < 2 / 255)
        }

        @Test(arguments: [false, true])
        func cursorColorDoesNotChangeTheBrandOrSuccessColors(dark: Bool) throws {
            let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
            var colors: [NSColor] = []
            appearance.performAsCurrentDrawingAppearance {
                colors = [GanchoTokens.Palette.brandGreen, GanchoTokens.Palette.success]
                    .compactMap { NSColor($0).usingColorSpace(.sRGB) }
            }
            #expect(colors.count == 2)
            let expected = dark ? (0x30, 0xD1, 0x58) : (0x34, 0xC7, 0x59)
            for color in colors {
                #expect(abs(color.redComponent - CGFloat(expected.0) / 255) < 2 / 255)
                #expect(abs(color.greenComponent - CGFloat(expected.1) / 255) < 2 / 255)
                #expect(abs(color.blueComponent - CGFloat(expected.2) / 255) < 2 / 255)
            }
        }

        private func renderCursor(scale: Int, dark: Bool = false) throws -> NSBitmapImageRep {
            let image = RegionSelectionCursor.make().image
            let bitmap = try #require(
                NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: 32 * scale, pixelsHigh: 36 * scale,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = context
            let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
            appearance.performAsCurrentDrawingAppearance {
                image.draw(in: NSRect(x: 0, y: 0, width: 32 * scale, height: 36 * scale))
            }
            return bitmap
        }

        private func color(
            in bitmap: NSBitmapImageRep, at point: NSPoint, scale: Int
        ) throws -> NSColor {
            try #require(
                bitmap.colorAt(x: Int(point.x * CGFloat(scale)), y: Int(point.y * CGFloat(scale)))?
                    .usingColorSpace(.sRGB))
        }

        private func makeView(cursor: NSCursor = .crosshair) -> RegionSelectionView {
            RegionSelectionView(frame: NSRect(x: 0, y: 0, width: 300, height: 200), cursor: cursor)
        }
    }

    private final class RecordingCursor: NSCursor {
        private let count = Mutex(0)
        var updates: Int { count.withLock { $0 } }
        override func set() { count.withLock { $0 += 1 } }
    }
#endif
