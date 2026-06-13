import ClipboardCore
import GanchoAI
import GanchoDesign
import GanchoKit
import GanchoSync
import GanchoTelemetry
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// iOS companion shell (pre-alpha). Proves the honest capture story end to
/// end: intent-based reads only (capture button, UIPasteControl, share
/// extension inbox), detect-before-read hints, and NO background polling —
/// the App Review notes promise exactly this behavior.
@main
struct GanchoiOSApp: App {
    @State private var model = IOSAppModel()

    var body: some Scene {
        WindowGroup {
            // iPad gets the sidebar layout; iPhone keeps the stack.
            if UIDevice.current.userInterfaceIdiom == .pad {
                IPadSplitView()
                    .environment(model)
            } else {
                CaptureView()
                    .environment(model)
            }
        }
    }
}

@Observable
@MainActor
final class IOSAppModel {
    var captures: [ClipItem] = []
    var hints = IntentionalPasteboardSource.ContentHints()
    /// Transient feedback ("Saved" / "Already in your history").
    var saveNote: String?
    var query = ""
    var kindFilter: ClipContentKind?

    /// Sync boundary: pull-to-refresh forces a cycle. A `NoopSyncEngine`
    /// until the user is Pro on an iCloud-signed-in device; the adapter swaps
    /// in transparently — the pull-to-refresh UI contract is identical.
    private var syncEngine: any SyncEngine = NoopSyncEngine()
    private var syncEnabled = false
    private var tier: UserTier = .free
    private let purchases = StoreKitPurchaseHandler()

    init() {
        purchases.onTierChange = { [weak self] tier in
            guard let self else { return }
            self.tier = tier
            self.configureSync()
        }
        Task {
            tier = await purchases.currentTier()
            configureSync()
        }
    }

    /// Arms or disarms iCloud sync to match the current tier + account.
    /// Universal Purchase entitles the iPhone too, so a Pro Mac purchase
    /// turns sync on here after the next entitlement refresh.
    private func configureSync() {
        guard let grdb = store as? GRDBClipboardStore else { return }
        let iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
        let enable = SyncEnablement.shouldEnable(tier: tier, iCloudAvailable: iCloudAvailable)
        guard enable != syncEnabled else { return }
        syncEnabled = enable

        let previous = syncEngine
        Task { await previous.stop() }
        let stateURL = SharedStorageLocation.storeDirectory(appGroupID: SharedInbox.appGroupID)
            .appendingPathComponent("sync-state.plist")
        syncEngine = SyncEngineFactory.make(
            store: grdb, tier: tier, iCloudAvailable: iCloudAvailable,
            stateStore: .file(at: stateURL))
        let engine = syncEngine
        Task { try? await engine.start() }
    }

    /// Telemetry — opt-out-first, buckets only; no sender when opted out so
    /// the SDK never initializes. Records the launch on construction.
    private let telemetry: TelemetryPipeline = {
        let optedOut = UserDefaults.standard.bool(forKey: "telemetry-opted-out")
        let sender: (any TelemetrySending)? =
            optedOut ? nil : TelemetryDeckSender(appID: GanchoTelemetryConfig.appID)
        let pipeline = TelemetryPipeline(sender: sender, optedOut: optedOut)
        pipeline.record(.appLaunched)
        return pipeline
    }()

    func forceSync() async {
        // Start = "run a sync cycle now" on the boundary; the CloudKit
        // adapter gives it real semantics on the device-day.
        try? await syncEngine.start()
        await refreshHints()
    }

    func search() async {
        guard let grdb = store as? GRDBClipboardStore, !query.isEmpty else {
            captures = (try? await store.items(offset: 0, limit: 50)) ?? []
            if let kindFilter {
                captures = captures.filter { $0.kind == kindFilter }
            }
            return
        }
        let kinds: Set<ClipContentKind>? = kindFilter.map { [$0] }
        captures =
            (try? await grdb.search(
                ClipSearchQuery(text: query, kinds: kinds), limit: 50)) ?? []
    }

    /// 1-tap copy with haptic confirmation.
    func copyToPasteboard(_ item: ClipItem) async {
        guard let content = try? await store.content(for: item.id) else { return }
        switch content {
        case .text(let text):
            UIPasteboard.general.string = text
        case .binary(let data, _):
            UIPasteboard.general.image = UIImage(data: data)
        case .fileReferences(let paths):
            UIPasteboard.general.string = paths.joined(separator: "\n")
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func togglePin(_ item: ClipItem) async {
        guard let grdb = store as? GRDBClipboardStore else { return }
        try? await grdb.setPinned(id: item.id, !item.isPinned)
        await search()
    }

    func delete(_ item: ClipItem) async {
        try? await store.delete(id: item.id)
        await search()
    }

    private let source = IntentionalPasteboardSource()
    private let classifier = RuleClassifier()
    /// Durable store in the App Group container (shared family location);
    /// in-memory fallback keeps the app usable if the container is missing.
    let store: any ClipboardStore = {
        let directory = SharedStorageLocation.storeDirectory(
            appGroupID: SharedInbox.appGroupID)
        return (try? GRDBClipboardStore(directory: directory)) ?? InMemoryClipboardStore()
    }()

    /// Metadata-only refresh — safe on every activation, never alerts.
    func refreshHints() async {
        hints = await source.hints()
        captures = (try? await store.items(offset: 0, limit: 50)) ?? []
    }

    /// The user-initiated read (system paste transparency applies).
    func saveClipboard() async {
        guard let capture = source.captureNow() else { return }
        await ingest(capture)
    }

    private func flashNote(_ text: String) {
        saveNote = text
        Task {
            try? await Task.sleep(for: .seconds(2))
            saveNote = nil
        }
    }

    /// Captures handed over by the share extension through the App Group.
    /// The extension already classified (tier 0); reuse its verdict.
    func drainSharedInbox() async {
        guard let inbox = SharedInbox.inAppGroup() else { return }
        for prepared in (try? inbox.drainPrepared()) ?? [] {
            await ingest(prepared.capture, precomputedKind: prepared.kind)
        }
    }

    /// UIPasteControl handoff: the system mediates the tap, so this path
    /// never shows an alert. Providers carry text, URLs, or images.
    func ingest(providers: [NSItemProvider]) {
        for provider in providers {
            if provider.canLoadObject(ofClass: UIImage.self) {
                _ = provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                    guard let png = (object as? UIImage)?.pngData() else { return }
                    Task { @MainActor in
                        await self?.ingest(
                            PasteboardCapture(
                                payload: .image(data: png, typeIdentifier: "public.png")))
                    }
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { [weak self] object, _ in
                    guard let text = object as? String, !text.isEmpty else { return }
                    Task { @MainActor in
                        await self?.ingest(PasteboardCapture(text: text))
                    }
                }
            }
        }
    }

    private func ingest(
        _ capture: PasteboardCapture, precomputedKind: ClipContentKind? = nil
    )
        async
    {
        let item = makeItem(from: capture, precomputedKind: precomputedKind)
        let content: ClipContent? =
            switch capture.payload {
            case .image(let data, let typeIdentifier):
                .binary(data: data, typeIdentifier: typeIdentifier)
            default:
                capture.textRepresentation.map { .text($0) }
            }
        // Dedupe-aware feedback: the store returns the EXISTING item when
        // the content hash matches — warn subtly instead of duplicating.
        let stored = try? await store.insert(item, content: content)
        if let stored { await syncEngine.enqueue([stored]) }
        flashNote(
            stored?.id == item.id
                ? String(localized: "Saved") : String(localized: "Already in your history"))
        captures = (try? await store.items()) ?? []
    }

    private func makeItem(
        from capture: PasteboardCapture, precomputedKind: ClipContentKind? = nil
    ) -> ClipItem {
        switch capture.payload {
        case .image(let data, let typeIdentifier):
            return ClipItem(
                kind: .image,
                preview: "Image (\(typeIdentifier), \(data.count) bytes)",
                contentHash: ClipItem.hash(of: data, kind: .image),
                sourceAppBundleID: capture.sourceAppBundleID)
        default:
            let raw = capture.textRepresentation ?? ""
            let kind = precomputedKind ?? classifier.classify(raw)
            let text = ContentNormalizer.canonicalText(raw, kind: kind)
            let item = ClipItem(
                kind: kind,
                preview: String(text.prefix(120)),
                contentHash: ClipItem.hash(of: text, kind: kind),
                sourceAppBundleID: capture.sourceAppBundleID)
            return SensitiveIngestionPolicy.decorate(
                item, finding: SensitiveDataDetector().detect(text), originalText: text)
        }
    }
}

struct CaptureView: View {
    @Environment(IOSAppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                Section("Pasteboard") {
                    hintsRow
                    Button("Save clipboard", systemImage: "square.and.arrow.down") {
                        Task { await model.saveClipboard() }
                    }
                    .accessibilityIdentifier("capture-button")
                    PasteControlView { providers in
                        model.ingest(providers: providers)
                    }
                    .frame(height: 36)
                    .accessibilityIdentifier("paste-control")
                }

                Section("History") {
                    if model.captures.isEmpty {
                        emptyState
                    } else {
                        ForEach(model.captures) { item in
                            NavigationLink(value: item.id) {
                                ClipCard(item: item)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await model.delete(item) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    Task { await model.togglePin(item) }
                                } label: {
                                    Label(
                                        item.isPinned ? "Unpin" : "Pin",
                                        systemImage: item.isPinned ? "pin.slash" : "pin")
                                }
                                .tint(.orange)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    Task { await model.copyToPasteboard(item) }
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
            }
            .searchable(text: $model.query, prompt: Text("Search your clipboard"))
            .onChange(of: model.query) { _, _ in Task { await model.search() } }
            .navigationTitle("Gancho")
            .navigationDestination(for: UUID.self) { id in
                if let item = model.captures.first(where: { $0.id == id }) {
                    ClipDetailView(item: item)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    kindFilterMenu
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(Text("Settings"))
                }
            }
            .sheet(isPresented: $showSettings) { IOSSettingsView() }
            .refreshable { await model.forceSync() }
            .accessibilityIdentifier("capture-screen")
        }
        .task { await activate() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await activate() }
        }
    }

    private var kindFilterMenu: some View {
        @Bindable var model = self.model
        return Menu {
            Picker("Filter by type", selection: $model.kindFilter) {
                Text("All types").tag(ClipContentKind?.none)
                ForEach(ClipContentKind.allCases, id: \.self) { kind in
                    Label(LocalizedStringKey(kind.rawValue), systemImage: kind.symbolName)
                        .tag(ClipContentKind?.some(kind))
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .onChange(of: model.kindFilter) { _, _ in Task { await model.search() } }
        .accessibilityLabel(Text("Filter by type"))
    }

    /// Honest about the platform: no background capture exists on iOS.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            Text("Nothing captured yet.")
                .foregroundStyle(.secondary)
            Text(
                "iOS apps can't watch the clipboard in the background — no app can. Capture with the button above, the share sheet from any app, or a Shortcut on your Action Button."
            )
            .font(.footnote)
            .foregroundStyle(.tertiary)
        }
    }

    /// Foreground activation: metadata hints + extension inbox, no reads.
    private func activate() async {
        await model.refreshHints()
        await model.drainSharedInbox()
        await model.search()
    }

    @ViewBuilder
    private var hintsRow: some View {
        if let note = model.saveNote {
            Label(note, systemImage: "checkmark.circle")
                .foregroundStyle(.green)
                .accessibilityIdentifier("save-note")
        }
        if model.hints.hasContent {
            // The capture banner: detection happened WITHOUT reading; the
            // button is the explicit consent that triggers the read.
            HStack {
                Label(hintText, systemImage: "doc.on.clipboard")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Save it") {
                    Task { await model.saveClipboard() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .accessibilityIdentifier("pasteboard-hints")
        } else {
            Label("Pasteboard is empty", systemImage: "doc.on.clipboard")
                .foregroundStyle(.tertiary)
                .accessibilityIdentifier("pasteboard-hints")
        }
    }

    private var hintText: String {
        var parts: [String] = []
        if model.hints.probableWebURL { parts.append(String(localized: "link")) }
        if model.hints.probableWebSearch { parts.append(String(localized: "search text")) }
        if model.hints.number { parts.append(String(localized: "number")) }
        let detail = parts.isEmpty ? String(localized: "content") : parts.joined(separator: ", ")
        return String(localized: "Has \(detail) — not read yet")
    }
}

/// Per-kind detail: full content, dev actions, one-tap copy with haptics.
struct ClipDetailView: View {
    @Environment(IOSAppModel.self) private var model
    let item: ClipItem
    @State private var fullText = ""
    @State private var actionResult: String?

    var body: some View {
        List {
            Section {
                TypeBadge(kind: item.kind)
                Text(fullText.isEmpty ? item.preview : fullText)
                    .font(item.kind == .code ? .body.monospaced() : .body)
                    .textSelection(.enabled)
            }

            let actions = DevActions.actions(for: item.kind)
            if !actions.isEmpty {
                Section("Actions") {
                    ForEach(actions) { action in
                        Button(LocalizedStringKey(action.title)) {
                            actionResult = (try? action.transform(fullText)) ?? ""
                        }
                    }
                    if let actionResult, !actionResult.isEmpty {
                        Text(actionResult)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                        Button("Copy result", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = actionResult
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                    }
                }
            }

            Section {
                Button("Copy", systemImage: "doc.on.doc") {
                    Task { await model.copyToPasteboard(item) }
                }
                .accessibilityIdentifier("detail-copy")
            }
        }
        .navigationTitle(Text(LocalizedStringKey(item.kind.rawValue)))
        .task {
            if case .text(let text)? = try? await model.store.content(for: item.id) {
                fullText = text
            }
        }
    }
}

/// iOS settings: honest capture explainer + the Shortcuts gallery link.
struct IOSSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Capture on iPhone") {
                    Text(
                        "Gancho never reads your pasteboard in the background. Capture happens only when you act: the save button, the share sheet, or a Shortcut."
                    )
                    .font(.footnote)
                }
                Section("Shortcuts") {
                    Link(destination: URL(string: "https://gancho.app/shortcuts")!) {
                        Label("Example Shortcuts gallery", systemImage: "square.stack.3d.up")
                    }
                }
            }
            .navigationTitle(Text("Settings"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// `UIPasteControl` wrapper: the system button that pastes WITHOUT any
/// banner or alert, because the OS itself mediates the user's tap.
struct PasteControlView: UIViewRepresentable {
    let onPaste: ([NSItemProvider]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPaste: onPaste)
    }

    func makeUIView(context: Context) -> UIPasteControl {
        let control = UIPasteControl()
        control.target = context.coordinator.target
        return control
    }

    func updateUIView(_ control: UIPasteControl, context: Context) {}

    @MainActor
    final class Coordinator {
        let target: PasteTarget

        init(onPaste: @escaping ([NSItemProvider]) -> Void) {
            target = PasteTarget(onPaste: onPaste)
        }
    }

    /// Hidden responder the control targets; accepts text, URLs, images.
    @MainActor
    final class PasteTarget: UIResponder {
        private let onPaste: ([NSItemProvider]) -> Void

        init(onPaste: @escaping ([NSItemProvider]) -> Void) {
            self.onPaste = onPaste
            super.init()
            pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: [
                UTType.plainText.identifier,
                UTType.url.identifier,
                UTType.image.identifier,
            ])
        }

        override func paste(itemProviders: [NSItemProvider]) {
            onPaste(itemProviders)
        }
    }
}
