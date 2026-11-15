#if os(macOS)
    import AppKit

    /// The localized names of the running apps, kept from the workspace's
    /// insertions and removals. Every property read on a running app is a
    /// LaunchServices round trip, so only the first read touches every app.
    @MainActor
    final class RunningApplicationNames<App: Equatable> {
        private var entries: [(app: App, name: String?)]
        private let name: (App) -> String?

        init(seed: [App], name: @escaping (App) -> String?) {
            self.name = name
            entries = seed.map { ($0, name($0)) }
        }

        func apply(inserted: [App], removed: [App]) {
            entries.removeAll { entry in removed.contains(entry.app) }
            entries += inserted.map { ($0, name($0)) }
        }

        func reset(to apps: [App]) {
            entries = apps.map { ($0, name($0)) }
        }

        /// Names an app had not published when it arrived are read again here.
        func current() -> [String] {
            for index in entries.indices where entries[index].name == nil {
                entries[index].name = name(entries[index].app)
            }
            return entries.compactMap(\.name)
        }
    }

    /// The process-wide index, following `NSWorkspace.runningApplications`.
    @MainActor
    final class WorkspaceRunningApplicationNames {
        static let shared = WorkspaceRunningApplicationNames()

        private var index: RunningApplicationNames<NSRunningApplication>?
        private var observation: NSKeyValueObservation?

        func current() -> [String] {
            if let index { return index.current() }
            let workspace = NSWorkspace.shared
            // Registered before the seed, so no app arrives unseen in between.
            observation = workspace.observe(\.runningApplications, options: [.new, .old]) {
                [weak self] _, change in
                let kind = change.kind
                let inserted = change.newValue ?? []
                let removed = change.oldValue ?? []
                let apply = { @MainActor in
                    guard let index = self?.index else { return }
                    switch kind {
                    case .insertion, .removal: index.apply(inserted: inserted, removed: removed)
                    default: index.reset(to: NSWorkspace.shared.runningApplications)
                    }
                }
                if Thread.isMainThread {
                    MainActor.assumeIsolated { apply() }
                } else {
                    DispatchQueue.main.async { apply() }
                }
            }
            let created = RunningApplicationNames(
                seed: workspace.runningApplications, name: \.localizedName)
            index = created
            return created.current()
        }
    }
#endif
