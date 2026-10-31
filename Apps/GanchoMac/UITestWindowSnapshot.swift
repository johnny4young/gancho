import AppKit

#if DEBUG
    /// UI-test hook: renders one of Gancho's own windows to a PNG with
    /// `cacheDisplay`, so a design snapshot holds only this app's views. A
    /// screen-region capture would include any window covering it.
    /// Installed only with `-ui-test-snapshot-dir <directory>`.
    enum UITestWindowSnapshot {
        static let request = Notification.Name("com.johnny4young.gancho.ui-test.window-snapshot")

        static func installIfRequested() {
            let arguments = CommandLine.arguments
            guard let index = arguments.firstIndex(of: "-ui-test-snapshot-dir"),
                arguments.indices.contains(index + 1)
            else { return }
            let directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
            _ = DistributedNotificationCenter.default().addObserver(
                forName: request, object: nil, queue: .main
            ) { note in
                // "<token>|<window>|<file name>". The token is the render
                // directory's name, unique per run, so no other process can ask.
                guard let object = note.object as? String else { return }
                MainActor.assumeIsolated { capture(object, into: directory) }
            }
        }

        private static func capture(_ object: String, into directory: URL) {
            let parts = object.split(separator: "|", maxSplits: 2).map(String.init)
            guard parts.count == 3, parts[0] == directory.lastPathComponent,
                parts[2].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }),
                let window = NSApp.windows.first(where: { $0.isVisible && matches($0, parts[1]) }),
                // A popover's frame view draws a material the cache can't capture.
                let view =
                    parts[1] == "@popover"
                    ? window.contentView : window.contentView?.superview ?? window.contentView,
                let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else { return }
            try? data.write(
                to: directory.appendingPathComponent("\(parts[2]).png"), options: .atomic)
        }

        /// A window by title or accessibility identifier; `@sheet` and
        /// `@popover` are the visible sheet and popover, which have neither.
        private static func matches(_ window: NSWindow, _ selector: String) -> Bool {
            if selector == "@sheet" { return window.sheetParent != nil }
            if selector == "@popover" {
                return String(describing: type(of: window)).contains("Popover")
            }
            return window.title == selector || window.accessibilityIdentifier() == selector
        }
    }
#endif
