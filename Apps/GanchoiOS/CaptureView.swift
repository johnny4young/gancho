import ClipboardCore
import GanchoAI
import GanchoDesign
import GanchoKit
import GanchoSync
import GanchoTelemetry
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WidgetKit

/// The one sheet the capture screen can present at a time.
enum CaptureSheet: Identifiable {
    case settings
    case boards
    case peek(ClipItem)
    case move(ClipItem)
    case pro

    var id: String {
        switch self {
        case .settings: "settings"
        case .boards: "boards"
        case .peek(let clip): "peek-\(clip.id)"
        case .move(let clip): "move-\(clip.id)"
        case .pro: "pro"
        }
    }
}

// CaptureView coordinates the iOS capture surface, detail sheets, and history
// list today; keep this local until the screen can be split safely.
// swiftlint:disable type_body_length
struct CaptureView: View {
    // swiftlint:enable type_body_length
    @Environment(IOSAppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    /// One sheet at a time — Settings, the boards home, a clip peek, or the
    /// move-to-board sheet. A single `.sheet(item:)` because stacking several
    /// `.sheet` modifiers on one view is unreliable (two `isPresented` sheets
    /// silently drop one — that's why the boards home wouldn't open).
    @State private var activeSheet: CaptureSheet?
    @State private var showNewBoard = false
    @State private var newBoardName = ""
    @State private var renameTarget: Pinboard?
    @State private var renameField = ""
    @State private var path: [UUID] = []
    @State private var answer: IOSAppModel.ClipboardAnswer?
    @State private var isAsking = false
    @State private var askTask: Task<Void, Never>?

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                boardRail
                List {
                    if model.storageIsEphemeral { storageWarningSection }
                    syncStatusSection
                    pasteboardSection

                    if !model.query.isEmpty, model.askAvailable {
                        Section {
                            askRow
                        }
                    }

                    if model.visibleClips.isEmpty {
                        Section("History") { emptyState }
                    } else if model.isGroupedView {
                        // Pinned first, then Today / Yesterday / … date sections.
                        ForEach(model.sections) { group in
                            Section(sectionTitle(group.section)) {
                                ForEach(group.clips) { clipRow($0) }
                            }
                        }
                    } else {
                        Section("History") {
                            ForEach(model.visibleClips) { clipRow($0) }
                        }
                    }
                }
                .searchable(text: $model.query, prompt: Text("Search your clipboard"))
                .onChange(of: model.query) { _, _ in
                    askTask?.cancel()
                    askTask = nil
                    isAsking = false
                    answer = nil
                    Task { await model.search() }
                }
                .onChange(of: model.kindFilter) { _, _ in
                    Task { await model.search() }
                }
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
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            activeSheet = .boards
                        } label: {
                            Image(systemName: "rectangle.stack")
                        }
                        .accessibilityLabel(Text("Boards"))
                        .accessibilityIdentifier("boards-home-open")
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            activeSheet = .settings
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel(Text("Settings"))
                    }
                }
                .sheet(item: $activeSheet) { sheet in
                    switch sheet {
                    case .settings: IOSSettingsView()
                    case .boards: BoardsHomeView()
                    case .peek(let clip):
                        // Wrap the peek in its own NavigationStack so it gets a
                        // titled bar + an explicit Done button (the codebase
                        // sheet convention) — drag-to-dismiss isn't discoverable.
                        // The pushed (deep-link) path keeps the parent's back
                        // button, so ClipDetailView itself stays unwrapped.
                        NavigationStack {
                            ClipDetailView(item: clip)
                                .toolbar {
                                    ToolbarItem(placement: .confirmationAction) {
                                        Button("Done") { activeSheet = nil }
                                    }
                                }
                        }
                    case .move(let clip): MoveToBoardSheet(item: clip)
                    case .pro:
                        // Wrapped like the peek: a titled bar + explicit Done,
                        // since drag-to-dismiss isn't discoverable.
                        NavigationStack {
                            ProInfoView()
                                .toolbar {
                                    ToolbarItem(placement: .confirmationAction) {
                                        Button("Done") { activeSheet = nil }
                                    }
                                }
                        }
                    }
                }
                .onChange(of: model.proGateTick) { _, _ in
                    // A free-tier limit was hit somewhere — show the Pro screen
                    // rather than letting a vanishing note dead-end the user.
                    activeSheet = .pro
                }
                .alert("New board", isPresented: $showNewBoard) {
                    TextField("Board name", text: $newBoardName)
                    Button("Cancel", role: .cancel) {}
                    Button("Create") { model.createBoard(named: newBoardName) }
                }
                .alert("Rename board", isPresented: renamePresented) {
                    TextField("Board name", text: $renameField)
                    Button("Cancel", role: .cancel) {}
                    Button("Rename") {
                        if let renameTarget { model.renameBoard(renameTarget, name: renameField) }
                    }
                }
                .refreshable { await model.forceSync() }
                .accessibilityIdentifier("capture-screen")
            }
        }
        .task { await activate() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await activate() }
        }
        // Re-sense the pasteboard every time the app comes forward — the most
        // reliable signal (scenePhase can miss). This is how the capture card
        // tracks what you just copied in another app.
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
        ) { _ in
            Task { await model.refreshHints() }
        }
        // …and when the pasteboard changes while we're foreground (e.g. you tap
        // Copy on a clip), so the card reflects it without a round-trip away.
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) {
            _ in
            Task { await model.refreshHints() }
        }
        .onChange(of: model.deepLinkClipID) { _, id in
            guard let id else { return }
            path = [id]
            model.deepLinkClipID = nil
        }
    }

    /// "Ask your clipboard": a one-tap button to answer the typed query from
    /// history, the spinner while it runs, and the grounded answer card. The
    /// section only appears while searching and when the model is available.
    @ViewBuilder private var askRow: some View {
        if isAsking {
            Label("Thinking…", systemImage: "sparkles")
                .font(.callout).foregroundStyle(.secondary)
                .symbolEffect(.pulse, options: .repeating)
        } else if let answer {
            answerCard(answer)
        } else {
            Button {
                runAsk()
            } label: {
                Label("Ask gancho", systemImage: "sparkles")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(GanchoTokens.Palette.accent)
            }
            .accessibilityIdentifier("ask-clipboard")
        }
    }

    private func answerCard(_ answer: IOSAppModel.ClipboardAnswer) -> some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            HStack {
                Label("Answer", systemImage: "sparkles").font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    self.answer = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain).foregroundStyle(.tertiary)
                .accessibilityLabel(Text("Dismiss"))
            }
            Text(answer.answer)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            if !answer.sources.isEmpty {
                Text("Sources").font(.caption).foregroundStyle(.secondary)
                ForEach(answer.sources.prefix(4)) { clip in
                    Button {
                        Task { await model.copyToPasteboard(clip) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: clip.kind.symbolName)
                                .font(.caption)
                                .foregroundStyle(GanchoTokens.Palette.kindTint(for: clip.kind))
                            Text(clip.preview).font(.callout).lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "doc.on.doc")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .accessibilityIdentifier("ask-answer")
    }

    private func runAsk() {
        let question = model.query
        askTask?.cancel()
        answer = nil
        isAsking = true
        askTask = Task { @MainActor in
            let result = await model.askClipboard(question)
            guard !Task.isCancelled, model.query == question else { return }
            isAsking = false
            answer = result
            askTask = nil
        }
    }

    // The row body intentionally keeps gesture, navigation, and thumbnail
    // wiring together so UI behavior remains obvious during this lint adoption.
    // swiftlint:disable function_body_length
    /// Boards axis (above the type filter), as a horizontal rail of chips: All
    /// clips · Favorites · user boards · New board. The active chip takes the
    /// system accent; long-press a user board to rename or delete it.
    /// One history row: tap pushes the detail (the peek lands in a later phase),
    /// swipe gives Copy / Pin / Delete, and reaching the last rows pulls the next
    /// page (infinite scroll).
    @ViewBuilder
    private func clipRow(_ item: ClipItem) -> some View {
        // swiftlint:enable function_body_length
        Button {
            activeSheet = .peek(item)
        } label: {
            ClipCard(item: item, thumbnail: model.thumbnails.cached(for: item.id))
        }
        .buttonStyle(.plain)
        .task(id: item.id) { await model.thumbnails.ensureLoaded(item) }
        .onAppear { Task { await model.loadMoreIfNeeded(item) } }
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
            Button {
                activeSheet = .move(item)
            } label: {
                Label("Board", systemImage: "tray.and.arrow.down")
            }
            .tint(.indigo)
        }
        .contextMenu {
            Button {
                Task { await model.copyToPasteboard(item) }
            } label: {
                Label("Copy", systemImage: "doc.on.clipboard")
            }
            if !item.isSensitive {
                ShareLink(item: item.preview) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            Button {
                Task { await model.togglePin(item) }
            } label: {
                Label(
                    item.isPinned ? "Unpin" : "Pin",
                    systemImage: item.isPinned ? "pin.slash" : "pin")
            }
            Divider()
            Button(role: .destructive) {
                Task { await model.delete(item) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } preview: {
            clipPreview(item)
        }
    }

    /// The rich preview iOS lifts under a long-press: the image renders for
    /// image clips, otherwise the (masked-if-sensitive) text preview.
    @ViewBuilder
    private func clipPreview(_ item: ClipItem) -> some View {
        if item.kind == .image, !item.isSensitive,
            let thumbnail = model.thumbnails.cached(for: item.id)
        {
            thumbnail
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 300, maxHeight: 220)
        } else {
            Text(item.preview)
                .font(item.kind == .code ? .body.monospaced() : .body)
                .padding()
                .frame(maxWidth: 300, alignment: .leading)
        }
    }

    private func sectionTitle(_ section: ClipSection) -> LocalizedStringKey {
        switch section {
        case .pinned: "Pinned"
        case .date(let bucket): bucketTitle(bucket)
        }
    }

    private func bucketTitle(_ bucket: DateBucket) -> LocalizedStringKey {
        switch bucket {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .thisMonth: "This month"
        case .lastMonth: "Last month"
        case .thisYear: "This year"
        case .lastYear: "Last year"
        case .older: "Older"
        }
    }

    private var boardRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: GanchoTokens.Spacing.xs) {
                railChip(
                    Text("All clips"), systemImage: "tray.full",
                    isActive: model.selectedBoardID == nil
                ) {
                    select(board: nil)
                }
                ForEach(model.boards) { board in
                    railChip(
                        board.isSystem ? Text("Favorites") : Text(verbatim: board.name),
                        systemImage: board.sfSymbol,
                        isActive: model.selectedBoardID == board.id,
                        dotColor: board.isSystem ? nil : BoardColors.color(for: board)
                    ) {
                        select(board: board.id)
                    }
                    .contextMenu {
                        if !board.isSystem {
                            Button("Rename board…") {
                                renameField = board.name
                                renameTarget = board
                            }
                            Button("Delete board", role: .destructive) {
                                model.deleteBoard(board)
                            }
                        }
                    }
                }
                Button {
                    newBoardName = ""
                    showNewBoard = true
                } label: {
                    Label("New board…", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, GanchoTokens.Spacing.sm)
                        .padding(.vertical, GanchoTokens.Spacing.xs)
                        .background(.quaternary, in: Capsule())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("board-new")
            }
            .padding(.horizontal, GanchoTokens.Spacing.md)
            .padding(.vertical, GanchoTokens.Spacing.xs)
        }
        .accessibilityIdentifier("board-rail")
    }

    private func railChip(
        _ label: Text, systemImage: String, isActive: Bool, dotColor: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let dotColor, !isActive {
                    Circle().fill(dotColor).frame(width: 8, height: 8)
                } else {
                    Image(systemName: systemImage).font(.caption)
                }
                label.font(.subheadline.weight(.medium)).lineLimit(1)
            }
            .padding(.horizontal, GanchoTokens.Spacing.sm)
            .padding(.vertical, GanchoTokens.Spacing.xs)
            .background(
                isActive ? AnyShapeStyle(GanchoTokens.Palette.accent) : AnyShapeStyle(.quaternary),
                in: Capsule()
            )
            .foregroundStyle(isActive ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
    }

    private func select(board id: UUID?) {
        model.selectBoard(id)
    }

    private var renamePresented: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
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
        .accessibilityLabel(Text("Filter by type"))
    }

    private var hasActiveFilter: Bool {
        model.kindFilter != nil || model.selectedBoardID != nil
    }

    private func clearFilters() {
        model.kindFilter = nil
        model.selectBoard(nil)
    }

    /// Branches on context so it never lies: a search with no hits, a filter
    /// that excluded everything, or a genuinely empty history (the honest
    /// no-background-capture explanation). Before the split, "Nothing captured
    /// yet" showed up mid-search even when there were clips.
    @ViewBuilder private var emptyState: some View {
        if !model.query.isEmpty {
            VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
                Text("No clips match “\(model.query)”.")
                    .foregroundStyle(.secondary)
                if hasActiveFilter {
                    Button("Clear filters") { clearFilters() }
                        .font(.footnote)
                }
            }
        } else if hasActiveFilter {
            VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
                Text("No clips in this filter.")
                    .foregroundStyle(.secondary)
                Button("Clear filters") { clearFilters() }
                    .font(.footnote)
            }
        } else {
            VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
                Text("Nothing captured yet.")
                    .foregroundStyle(.secondary)
                Text(
                    // swiftlint:disable:next line_length
                    "iOS apps can't watch the clipboard in the background — no app can. Capture with the button above, the share sheet from any app, or a Shortcut on your Action Button."
                )
                .font(.footnote)
                .foregroundStyle(.tertiary)
            }
        }
    }

    /// Foreground activation: metadata hints + extension inbox, no reads.
    private func activate() async {
        model.syncNow()
        await model.refreshHints()
        await model.drainSharedInbox()
        await model.refreshBoards()
        await model.search()
    }

    /// The consensual capture card (the design's Pasteboard section). gancho
    /// senses the clipboard's TYPE via `detectPatterns` — no read, no "pasted
    /// from" banner — and the green `UIPasteControl` is the user's one-tap "yes,
    /// save this". Privacy is the function, not an apology.
    @ViewBuilder private var pasteboardSection: some View {
        Section {
            if let note = model.saveNote {
                Label(note, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(GanchoTokens.Palette.success)
                    .accessibilityIdentifier("save-note")
            }
            VStack(spacing: 0) {
                HStack(spacing: 11) {
                    captureTile
                    VStack(alignment: .leading, spacing: 4) {
                        Text(senseTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        if model.hints.hasContent {
                            if alreadyCaptured {
                                captureTag(Text("Saved"), tint: GanchoTokens.Palette.success)
                            } else {
                                captureTag(
                                    Text("not read yet"), tint: GanchoTokens.Palette.warning)
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    PasteControlView { providers in model.ingest(providers: providers) }
                        .frame(width: 108, height: 34)
                }
                .padding(.vertical, 10)
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.caption)
                        .foregroundStyle(GanchoTokens.Palette.accent)
                    Text(
                        "Gancho never reads your clipboard on its own. It only sees the type until you tap Save."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 9)
            }
            .accessibilityIdentifier("pasteboard-capture")
        } header: {
            HStack {
                Text("Pasteboard")
                Spacer()
                Label("sensed, not read", systemImage: "shield.lefthalf.filled")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textCase(nil)
            }
        }
    }

    private var captureTile: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(GanchoTokens.Palette.accent.opacity(0.15))
            .frame(width: 38, height: 38)
            .overlay {
                Image(systemName: senseSymbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(GanchoTokens.Palette.accent)
            }
    }

    /// Amber "not read yet" pill.
    private func captureTag(_ text: Text, tint: Color) -> some View {
        text
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.16), in: Capsule())
    }

    /// True when the copy currently on the clipboard is the one we just saved
    /// (matched by the pasteboard's change counter — metadata, no read).
    private var alreadyCaptured: Bool {
        model.lastCapturedChangeCount != nil
            && model.hints.changeCount == model.lastCapturedChangeCount
    }

    /// What `detectPatterns` sensed, as a title — derived without reading.
    private var senseTitle: LocalizedStringKey {
        guard model.hints.hasContent else { return "Pasteboard is empty" }
        if model.hints.probableWebURL { return "A link is on your clipboard" }
        if model.hints.probableWebSearch { return "Search text is on your clipboard" }
        if model.hints.number { return "A number is on your clipboard" }
        return "Something is on your clipboard"
    }

    private var senseSymbol: String {
        if model.hints.probableWebURL { return "link" }
        if model.hints.probableWebSearch { return "magnifyingglass" }
        if model.hints.number { return "number" }
        return "doc.on.clipboard"
    }

    /// Shown only when the durable store failed to open — captures are running
    /// in memory and will be lost on relaunch. Honest beats silent.
    private var storageWarningSection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("History isn't being saved").font(.subheadline.weight(.semibold))
                    Text(
                        "Gancho couldn't open its secure storage. Captures will vanish when you quit the app."
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .foregroundStyle(GanchoTokens.Palette.danger)
            }
            .accessibilityIdentifier("storage-warning")
        }
    }

    /// iCloud sync indicator. The steady states (off, synced) show nothing —
    /// the "ready to paste" Live Activity carries sync status now, so the
    /// history doesn't spend a card on a green "Synced" that's almost always
    /// true. Only the transient and the actionable states surface here.
    @ViewBuilder
    private var syncStatusSection: some View {
        switch model.syncStatus {
        case .idle, .upToDate:
            EmptyView()
        case .syncing:
            syncRow(Text("Syncing…"), "arrow.triangle.2.circlepath")
        case .pending(let count):
            syncRow(
                Text("\(Text("Waiting to sync")) · \(String(count))"), "arrow.up.circle")
        case .paused(let cause):
            syncRow(
                Text(causeText(cause)), "pause.circle", tint: GanchoTokens.Palette.warning,
                retry: true)
        case .failed(let cause):
            syncRow(
                Text(causeText(cause)), "exclamationmark.icloud",
                tint: GanchoTokens.Palette.danger, retry: true)
        }
    }

    private func syncRow(
        _ text: Text, _ symbol: String, tint: Color = .secondary, retry: Bool = false
    ) -> some View {
        Section {
            HStack {
                Label {
                    text
                } icon: {
                    // "Synced" reads green (a state); paused/failed warn — like macOS.
                    Image(systemName: symbol).foregroundStyle(tint)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                // A paused/failed sync was informational only; give it a way out.
                if retry {
                    Spacer(minLength: GanchoTokens.Spacing.sm)
                    Button("Retry") { model.syncNow() }
                        .font(.footnote)
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("sync-retry")
                }
            }
            .accessibilityIdentifier("sync-status")
        }
    }

    private func causeText(_ cause: SyncInterruption) -> LocalizedStringKey {
        switch cause {
        case .iCloudFull: "iCloud storage is full"
        case .notSignedIn: "Not signed in to iCloud"
        case .offline: "No internet connection"
        case .unknown: "Sync error"
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
        // Styled as the design's green "Save" — a system paste button that
        // grants one-time access on tap, no "pasted from" banner.
        let config = UIPasteControl.Configuration()
        config.cornerStyle = .capsule
        config.displayMode = .iconAndLabel
        config.baseBackgroundColor = UIColor(GanchoTokens.Palette.accent)
        config.baseForegroundColor = .white
        let control = UIPasteControl(configuration: config)
        control.target = context.coordinator.target
        // Set the identifier on the system UIView itself: SwiftUI's
        // `.accessibilityIdentifier` modifier does not propagate onto a
        // `UIViewRepresentable`'s underlying view, so XCUITest could not find the
        // control by id. Make the wrapper element explicit too: on simulator
        // runners `UIPasteControl` can keep its internal label accessible while
        // leaving the outer control unqueryable by identifier.
        control.isAccessibilityElement = true
        control.accessibilityIdentifier = "paste-control"
        control.accessibilityLabel = String(localized: "Save clipboard")
        control.accessibilityTraits.insert(.button)
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
                UTType.image.identifier
            ])
        }

        override func paste(itemProviders: [NSItemProvider]) {
            onPaste(itemProviders)
        }
    }
}
