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
                // "<window title>|<file name>"; the name is a bare slug.
                guard let object = note.object as? String else { return }
                MainActor.assumeIsolated { capture(object, into: directory) }
            }
        }

        private static func capture(_ object: String, into directory: URL) {
            let parts = object.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                parts[1].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }),
                let window = NSApp.windows.first(where: { $0.isVisible && $0.title == parts[0] }),
                let view = window.contentView?.superview ?? window.contentView,
                let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else { return }
            try? data.write(
                to: directory.appendingPathComponent("\(parts[1]).png"), options: .atomic)
        }
    }
#endif
