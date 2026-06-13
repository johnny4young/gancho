import AppKit
import ClipboardCore
import GanchoAI
import GanchoKit
import SwiftUI

/// Central app state: wires monitor → classifier → GRDB store, owns the
/// paste-back service, preferences, retention, and the panel lifecycle.
@Observable
@MainActor
final class AppModel {
    private(set) var recentItems: [ClipItem] = []
    var monitorStatus: MonitorStatus { monitor.status }

    /// Durable store under Application Support; falls back to in-memory if
    /// the disk store cannot open (never block launch on a storage error).
    let store: any ClipboardStore
    let grdbStore: GRDBClipboardStore?

    let monitor: MacPasteboardMonitor
    let pasteBack = PasteBackService()
    let privacyEvents = InMemoryPrivacyEventRecorder()
    let panel = PanelController()
    let welcomeWindow = WelcomeWindowController()

    private let classifier = RuleClassifier()
    private let sensitiveDetector = SensitiveDataDetector()
    private let defaults = UserDefaults.standard
    private var retentionTimer: Timer?

    var preferences: CapturePreferences {
        didSet {
            monitor.preferences = preferences
            preferences.save(to: defaults)
        }
    }

    var retentionPolicy: RetentionPolicy {
        didSet { retentionPolicy.save(to: defaults) }
    }

    /// Menu-bar agent by default; Settings can surface the Dock icon.
    var showInDock: Bool {
        didSet {
            defaults.set(showInDock, forKey: "show-in-dock")
            NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        }
    }

    init() {
        let directory = URL.applicationSupportDirectory
            .appendingPathComponent("Gancho", isDirectory: true)
        let grdb = try? GRDBClipboardStore(directory: directory)
        self.grdbStore = grdb
        self.store = grdb ?? InMemoryClipboardStore()

        let loadedPreferences = CapturePreferences.load(from: defaults)
        preferences = loadedPreferences
        retentionPolicy = RetentionPolicy.load(from: defaults)
        showInDock = defaults.bool(forKey: "show-in-dock")

        monitor = MacPasteboardMonitor(preferences: loadedPreferences)
        monitor.denylist = SourceAppDenylist.load(from: defaults)
        monitor.onCapture = { [weak self] capture in
            self?.ingest(capture)
        }
        monitor.onIgnore = { [weak self] reason in
            self?.privacyEvents.record(IgnoredCaptureEvent(reason: reason))
        }
        monitor.start()
        scheduleRetention()
        panel.attach(model: self)
        Task { await refreshRecents() }

        // UI-test hook: deterministic panel access without the global hotkey.
        if CommandLine.arguments.contains("-open-panel-on-launch") {
            Task { panel.show(model: self) }
        } else if !defaults.bool(forKey: "has-seen-welcome") {
            Task { welcomeWindow.show(model: self) }
        }
    }

    // MARK: - Capture pipeline

    private func ingest(_ capture: PasteboardCapture) {
        let (item, content) = Self.makeItem(
            from: capture, classifier: classifier, detector: sensitiveDetector,
            sensitiveLifetime: retentionPolicy.sensitiveLifetime)
        Task {
            try? await store.insert(item, content: content)
            await refreshRecents()
        }
    }

    func refreshRecents() async {
        recentItems = (try? await store.items(offset: 0, limit: 50)) ?? []
    }

    /// Capture payload → classified, normalized, sensitivity-decorated clip
    /// plus its full content for the store.
    static func makeItem(
        from capture: PasteboardCapture,
        classifier: RuleClassifier,
        detector: SensitiveDataDetector,
        sensitiveLifetime: TimeInterval
    ) -> (ClipItem, ClipContent?) {
        switch capture.payload {
        case .image(let data, let typeIdentifier):
            let item = ClipItem(
                kind: .image,
                preview: "Image (\(data.count) bytes)",
                contentHash: ClipItem.hash(of: data, kind: .image),
                sourceAppBundleID: capture.sourceAppBundleID)
            return (item, .binary(data: data, typeIdentifier: typeIdentifier))
        case .fileReferences(let urls):
            let paths = urls.map(\.path)
            let item = ClipItem(
                kind: .fileReference,
                preview: urls.map(\.lastPathComponent).joined(separator: ", "),
                contentHash: ClipItem.hash(of: paths.joined(separator: "\n"), kind: .fileReference),
                sourceAppBundleID: capture.sourceAppBundleID)
            return (item, .fileReferences(paths))
        case .richText(let rtf, let plain):
            let text = plain ?? ""
            let item = decoratedTextItem(
                text: text, capture: capture, classifier: classifier, detector: detector,
                sensitiveLifetime: sensitiveLifetime)
            return (
                item,
                item.isSensitive ? .text(text) : .binary(data: rtf, typeIdentifier: "public.rtf")
            )
        default:
            let text = capture.textRepresentation ?? ""
            let item = decoratedTextItem(
                text: text, capture: capture, classifier: classifier, detector: detector,
                sensitiveLifetime: sensitiveLifetime)
            return (item, .text(ContentNormalizer.canonicalText(text, kind: item.kind)))
        }
    }

    private static func decoratedTextItem(
        text: String, capture: PasteboardCapture, classifier: RuleClassifier,
        detector: SensitiveDataDetector, sensitiveLifetime: TimeInterval
    ) -> ClipItem {
        let kind = classifier.classify(text)
        let canonical = ContentNormalizer.canonicalText(text, kind: kind)
        let item = ClipItem(
            kind: kind,
            preview: String(canonical.prefix(120)),
            contentHash: ClipItem.hash(of: canonical, kind: kind),
            sourceAppBundleID: capture.sourceAppBundleID)
        return SensitiveIngestionPolicy.decorate(
            item, finding: detector.detect(canonical), originalText: canonical,
            sensitiveLifetime: sensitiveLifetime)
    }

    // MARK: - Actions

    /// Paste a stored clip into the frontmost app (panel Enter / menu click).
    func paste(_ item: ClipItem, asPlainText: Bool = false) {
        Task {
            guard let content = try? await store.content(for: item.id) else { return }
            panel.hide()
            // Give focus one beat to return to the previous app.
            try? await Task.sleep(for: .milliseconds(80))
            pasteBack.paste(content, asPlainText: asPlainText)
            // Activation metric (local, content-free): first paste-back ever.
            if defaults.object(forKey: "first-pasteback-at") == nil {
                defaults.set(Date().timeIntervalSince1970, forKey: "first-pasteback-at")
            }
            try? await store.insert(item, content: nil)  // move-to-top
            await refreshRecents()
        }
    }

    func togglePause() {
        if monitor.status == .running {
            monitor.stop()
        } else {
            monitor.start()
        }
    }

    func togglePrivateMode() {
        preferences.isPrivateModePaused.toggle()
    }

    func ignoreNextCopy() {
        monitor.ignoreNextCopy()
    }

    // MARK: - Pins & boards

    private(set) var boards: [Pinboard] = []

    func togglePin(_ item: ClipItem) {
        guard let grdbStore else { return }
        Task {
            // Free-tier ceiling; the paywall UX lands with monetization.
            if !item.isPinned {
                let count = (try? await grdbStore.pinnedCount()) ?? 0
                guard PinLimits.canPin(currentPinCount: count, isPro: false) else { return }
            }
            try? await grdbStore.setPinned(id: item.id, !item.isPinned)
            await refreshRecents()
        }
    }

    func refreshBoards() async {
        guard let grdbStore else { return }
        boards = (try? await grdbStore.pinboards()) ?? []
    }

    func assign(_ item: ClipItem, toBoard board: Pinboard?) {
        guard let grdbStore else { return }
        Task {
            try? await grdbStore.assign(clipID: item.id, toBoard: board?.id)
            await refreshRecents()
        }
    }

    func createBoard(named name: String) {
        guard let grdbStore else { return }
        Task {
            let count = (try? await grdbStore.pinboards().count) ?? 0
            guard PinLimits.canCreatePinboard(currentBoardCount: count, isPro: false) else {
                return
            }
            try? await grdbStore.createPinboard(name: name)
            await refreshBoards()
        }
    }

    // MARK: - Retention

    private func scheduleRetention() {
        runRetention()
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.runRetention() }
        }
    }

    private func runRetention() {
        guard let grdbStore else { return }
        let policy = retentionPolicy
        Task {
            try? await RetentionEngine(store: grdbStore).runPurge(policy: policy)
            await refreshRecents()
        }
    }
}
