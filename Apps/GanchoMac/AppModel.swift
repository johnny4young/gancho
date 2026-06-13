import AppIntents
import AppKit
import ClipboardCore
import GanchoAI
import GanchoKit
import KeyboardShortcuts
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
    let privacyCenterWindow = PrivacyCenterWindowController()
    let paywallWindow = PaywallWindowController()
    let permissionWindow = PasteboardPermissionWindowController()
    let libraryWindow = LibraryWindowController()

    /// Entitlement; purchases flip this when IAP lands.
    var tier: UserTier {
        didSet { tier.save(to: defaults) }
    }

    private let classifier = RuleClassifier()
    private let sensitiveDetector = SensitiveDataDetector()
    private let defaults = UserDefaults.standard
    private var retentionTimer: Timer?
    private let screenShareDetector = ScreenShareDetector()
    private var screenShareTimer: Timer?

    /// Opt-out for the share auto-pause (on by default).
    var autoPauseOnScreenShare: Bool {
        didSet { defaults.set(autoPauseOnScreenShare, forKey: "auto-pause-screen-share") }
    }

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
        autoPauseOnScreenShare =
            defaults.object(forKey: "auto-pause-screen-share") as? Bool ?? true
        tier = UserTier.load(from: defaults)

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
        scheduleScreenShareWatch()
        panel.attach(model: self)
        // Intents resolve the SAME model instance the UI uses.
        AppDependencyManager.shared.add(dependency: self)
        KeyboardShortcuts.onKeyUp(for: .togglePrivateMode) { [weak self] in
            self?.togglePrivateMode()
        }
        KeyboardShortcuts.onKeyUp(for: .cyclicPaste) { [weak self] in
            self?.cyclicPaste()
        }
        Task { await refreshRecents() }

        // UI-test hook: deterministic panel access without the global hotkey.
        if CommandLine.arguments.contains("-open-panel-on-launch") {
            Task { panel.show(model: self) }
        } else if !defaults.bool(forKey: "has-seen-welcome") {
            Task { welcomeWindow.show(model: self) }
        } else if monitor.status == .deniedByPrivacySettings {
            Task { permissionWindow.show(model: self) }
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

    /// Paste with a pure transform applied at paste time.
    func paste(_ item: ClipItem, transform: PasteTransform) {
        Task {
            guard case .text(let text)? = try? await store.content(for: item.id) else {
                paste(item, asPlainText: transform == .plainText)
                return
            }
            panel.hide()
            try? await Task.sleep(for: .milliseconds(80))
            pasteBack.paste(.text(transform.apply(to: text)), asPlainText: true)
            try? await store.insert(item, content: nil)
            await refreshRecents()
        }
    }

    /// Cyclic quick-paste: each invocation pastes the NEXT history item
    /// (wraps around). Resets to the top after 8s of silence.
    private var cycleIndex = 0
    private var lastCycleAt = Date.distantPast

    func cyclicPaste() {
        if Date().timeIntervalSince(lastCycleAt) > 8 { cycleIndex = 0 }
        lastCycleAt = Date()
        guard !recentItems.isEmpty else { return }
        let item = recentItems[cycleIndex % recentItems.count]
        cycleIndex += 1
        paste(item)
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
                guard PinLimits.canPin(currentPinCount: count, isPro: tier == .pro) else {
                    paywallWindow.show(trigger: .freeLimitReached, model: self)
                    return
                }
            }
            try? await grdbStore.setPinned(id: item.id, !item.isPinned)
            await refreshRecents()
        }
    }

    /// The signature gesture: clip → permanent snippet (⌘S in the panel).
    func promoteToSnippet(_ item: ClipItem) {
        guard let grdbStore else { return }
        Task {
            let count = (try? await grdbStore.snippetCount()) ?? 0
            guard SnippetLimits.canPromote(currentSnippetCount: count, isPro: tier == .pro)
            else {
                paywallWindow.show(trigger: .freeLimitReached, model: self)
                return
            }
            try? await grdbStore.promoteToSnippet(id: item.id)
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
            guard PinLimits.canCreatePinboard(currentBoardCount: count, isPro: tier == .pro)
            else {
                paywallWindow.show(trigger: .freeLimitReached, model: self)
                return
            }
            try? await grdbStore.createPinboard(name: name)
            await refreshBoards()
        }
    }

    // MARK: - Denylist & settings portability

    var denylistEntries: [String] {
        let effective = SourceAppDenylist.suggestedBundleIDs
            .subtracting(monitor.denylist.disabledSuggestions)
            .union(monitor.denylist.userBundleIDs)
        return effective.sorted()
    }

    func addToDenylist(_ bundleID: String) {
        monitor.denylist.add(bundleID)
        monitor.denylist.save(to: defaults)
    }

    func removeFromDenylist(_ bundleID: String) {
        monitor.denylist.remove(bundleID)
        monitor.denylist.save(to: defaults)
    }

    /// Preferences only — never clips (reinstall portability).
    func settingsSnapshot() throws -> SettingsSnapshot {
        SettingsSnapshot(
            retention: retentionPolicy,
            capturePreferencesJSON: (try? JSONEncoder().encode(preferences)) ?? Data(),
            appSettings: [
                "panel-position": panel.position.rawValue,
                "show-in-dock": showInDock ? "true" : "false",
            ])
    }

    func apply(_ snapshot: SettingsSnapshot) {
        retentionPolicy = snapshot.retention
        if let prefs = try? JSONDecoder().decode(
            CapturePreferences.self, from: snapshot.capturePreferencesJSON)
        {
            preferences = prefs
        }
        if let raw = snapshot.appSettings["panel-position"],
            let position = PanelPosition(rawValue: raw)
        {
            panel.position = position
        }
        if let dock = snapshot.appSettings["show-in-dock"] {
            showInDock = dock == "true"
        }
    }

    private func scheduleScreenShareWatch() {
        screenShareTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let sharing =
                    self.autoPauseOnScreenShare
                    && self.screenShareDetector.isScreenSharePresumed()
                if self.monitor.pausedForScreenShare != sharing {
                    self.monitor.pausedForScreenShare = sharing
                }
            }
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
        let tier = tier
        Task {
            try? await RetentionEngine(store: grdbStore).runPurge(policy: policy)
            try? await TierEnforcement(store: grdbStore).enforce(tier: tier)
            await refreshRecents()
        }
    }
}
