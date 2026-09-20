#if canImport(AppKit)
    import AppKit

    /// A single Gancho hook and precision crosshair, drawn as a scalable vector.
    /// The hot spot is the cross intersection, not the eyelet or the hook tip.
    @MainActor public enum RegionSelectionCursor {
        public static func make() -> NSCursor {
            let green = NSColor(GanchoTokens.Palette.regionSelectionCursor)
            let image = NSImage(size: NSSize(width: 32, height: 36), flipped: true) { _ in
                // Drawing can run on any thread. Keep mutable paths local to this invocation.
                let path = NSBezierPath(ovalIn: NSRect(x: -3.4, y: -2.55, width: 6.8, height: 5.1))
                var eyeletTransform = AffineTransform()
                eyeletTransform.translate(x: 16, y: 5)
                eyeletTransform.rotate(byDegrees: 28)
                path.transform(using: eyeletTransform)

                path.move(to: NSPoint(x: 16, y: 8))
                path.line(to: NSPoint(x: 16, y: 22.5))
                // A 300-degree curl leaves an open barb well below the crossbar.
                path.appendArc(
                    withCenter: NSPoint(x: 13.6, y: 22.5 + 2.4 * sqrt(3)), radius: 4.8,
                    startAngle: -60, endAngle: 240, clockwise: false)
                path.line(to: NSPoint(x: 10.1, y: 19.7))
                path.move(to: NSPoint(x: 4, y: 14))
                path.line(to: NSPoint(x: 28, y: 14))
                path.lineCapStyle = .round
                path.lineJoinStyle = .round

                // Both outlines are needed: the white halo on dark content,
                // and the dark keyline on white content. Never fill the open hook.
                NSColor(srgbRed: 19 / 255, green: 35 / 255, blue: 26 / 255, alpha: 1).setStroke()
                path.lineWidth = 4.3
                path.stroke()
                NSColor.white.setStroke()
                path.lineWidth = 3.45
                path.stroke()
                green.setStroke()
                path.lineWidth = 1.9
                path.stroke()
                return true
            }
            return NSCursor(image: image, hotSpot: NSPoint(x: 16, y: 14))
        }
    }
#endif
