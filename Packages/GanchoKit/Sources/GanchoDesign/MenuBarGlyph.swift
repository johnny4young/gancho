#if canImport(AppKit)
    import AppKit
    #if !STANDALONE_MENU_BAR
        import GanchoKit
    #endif

    /// The status item's mark: gancho's hook as a template image, which the
    /// system tints for every menu bar, with the coloured badge on a view above
    /// it. Also compiled into the menu-bar helper, so it uses AppKit only.
    public enum MenuBarGlyph {
        public static let hookSide: CGFloat = 18
        public static let badgeSide: CGFloat = 11
        /// The badged image is wider so the badge sits clear of the hook's curl.
        public static let badgedWidth: CGFloat = 24
        static let badgeCenter = NSPoint(x: 18.5, y: 5.5)

        /// The hook alone, or with a clear notch where the badge sits so the
        /// two never touch.
        public static func hookImage(badged: Bool) -> NSImage {
            badged ? badgedHook : plainHook
        }

        /// The same hook drawn at another size, for surfaces that show the mark large.
        public static func mark(side: CGFloat) -> NSImage {
            hook(width: side, notch: false, side: side)
        }

        private static let plainHook = hook(width: hookSide, notch: false)
        private static let badgedHook = hook(width: badgedWidth, notch: true)

        /// gancho's hook from the design's SVG path (viewBox 0 0 96 96) in
        /// AppKit's y-up space, with the menu-bar strokes (13 / 9) so it holds
        /// at 18 pt.
        private static func hook(
            width: CGFloat, notch: Bool, side: CGFloat = hookSide
        ) -> NSImage {
            let image = NSImage(
                size: NSSize(width: width, height: side), flipped: false
            ) { _ in
                NSGraphicsContext.saveGraphicsState()
                let transform = NSAffineTransform()
                transform.scale(by: side / 96)
                transform.concat()
                NSColor.black.set()

                let hook = NSBezierPath()
                hook.lineWidth = 13
                hook.lineCapStyle = .round
                hook.lineJoinStyle = .round
                hook.move(to: NSPoint(x: 50, y: 64))
                hook.line(to: NSPoint(x: 50, y: 39))
                hook.appendArc(
                    withCenter: NSPoint(x: 42.5, y: 26.01), radius: 15,
                    startAngle: 60, endAngle: 120, clockwise: true)
                hook.line(to: NSPoint(x: 31.5, y: 48.5))
                hook.stroke()

                let eye = NSBezierPath(ovalIn: NSRect(x: 42, y: 64, width: 16, height: 16))
                eye.lineWidth = 9
                eye.stroke()
                NSGraphicsContext.restoreGraphicsState()

                if notch {
                    NSGraphicsContext.current?.compositingOperation = .clear
                    NSBezierPath(ovalIn: badgeRect.insetBy(dx: -1, dy: -1)).fill()
                }
                return true
            }
            image.isTemplate = true
            return image
        }

        static var badgeRect: NSRect {
            NSRect(
                x: badgeCenter.x - badgeSide / 2, y: badgeCenter.y - badgeSide / 2,
                width: badgeSide, height: badgeSide)
        }

        /// Grey, ink or red, from the bytes the palette is built on: grey
        /// waits, ink is a mode, red needs the user.
        public static func fill(for badge: MenuBarBadge) -> NSColor {
            switch badge {
            case .denied: color(StatusBytes.dangerLight)
            case .paused, .ignoreNext: color(StatusBytes.ink3)
            case .privateMode, .agentRead, .stack: color(StatusBytes.ink)
            }
        }

        private static func color(_ bytes: (Int, Int, Int)) -> NSColor {
            NSColor(
                srgbRed: CGFloat(bytes.0) / 255, green: CGFloat(bytes.1) / 255,
                blue: CGFloat(bytes.2) / 255, alpha: 1)
        }

        /// White reads at 4.5:1 or more on every fill.
        public static func glyphColor(for badge: MenuBarBadge) -> NSColor { .white }

        /// The capture-state mark beside the menu header, tinted by the menu:
        /// a dot while capturing, a ring while paused or private, red when denied.
        public static func stateDot(for badge: MenuBarBadge?) -> NSImage {
            let side: CGFloat = 10
            let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
                let dot = NSBezierPath(ovalIn: rect.insetBy(dx: 1.75, dy: 1.75))
                switch badge {
                case .denied:
                    fill(for: .denied).setFill()
                    dot.fill()
                case .paused, .privateMode:
                    NSColor.black.setStroke()
                    dot.lineWidth = 1.5
                    dot.stroke()
                default:
                    NSColor.black.setFill()
                    NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
                }
                return true
            }
            image.isTemplate = badge != .denied
            return image
        }

        /// The badge itself: a white ring, the fill and the glyph.
        public static func badgeImage(_ badge: MenuBarBadge) -> NSImage {
            NSImage(size: NSSize(width: badgeSide, height: badgeSide), flipped: false) { rect in
                NSColor.white.setFill()
                NSBezierPath(ovalIn: rect).fill()
                fill(for: badge).setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5)).fill()
                let glyph = NSAttributedString(
                    string: badge.glyph,
                    attributes: [
                        .font: NSFont.systemFont(
                            ofSize: badge.glyph.count > 1 ? 6 : 7.5, weight: .heavy),
                        .foregroundColor: glyphColor(for: badge)
                    ])
                let size = glyph.size()
                glyph.draw(
                    at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
                return true
            }
        }

        /// Paints the hook on `button` and puts `badge` (or nothing) on the
        /// view above it, keeping the hook a template image. The badge is
        /// pinned to the button's centre, so it follows the variable-length
        /// item as it resizes for the wider badged image.
        @MainActor
        public static func apply(badge: MenuBarBadge?, to button: NSButton) {
            button.image = hookImage(badged: badge != nil)
            button.imagePosition = .imageOnly
            button.title = ""
            let badgeView =
                button.subviews.lazy.compactMap { $0 as? MenuBarBadgeView }.first
                ?? attachBadgeView(to: button)
            badgeView.isHidden = badge == nil
            badgeView.image = badge.map(badgeImage)
        }

        @MainActor
        private static func attachBadgeView(to button: NSButton) -> MenuBarBadgeView {
            let view = MenuBarBadgeView()
            view.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(view)
            NSLayoutConstraint.activate([
                view.widthAnchor.constraint(equalToConstant: badgeSide),
                view.heightAnchor.constraint(equalToConstant: badgeSide),
                view.centerXAnchor.constraint(
                    equalTo: button.centerXAnchor, constant: badgeCenter.x - badgedWidth / 2),
                // Layout runs top-down; the image's y runs up from its bottom.
                view.centerYAnchor.constraint(
                    equalTo: button.centerYAnchor, constant: hookSide / 2 - badgeCenter.y)
            ])
            return view
        }
    }

    /// The badge layer on the status button; not an accessibility element, the
    /// button's label already names the state.
    public final class MenuBarBadgeView: NSImageView {
        override public func isAccessibilityElement() -> Bool { false }
        override public func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
#endif
