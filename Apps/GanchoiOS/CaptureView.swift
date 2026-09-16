import ClipboardCore
import GanchoAI
import GanchoDesign
import GanchoKit
import GanchoTelemetry
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WidgetKit

/// The one sheet the capture screen can present at a time.
enum CaptureSheet: Identifiable {
    case settings
    case boards
    case boardAppearance(Pinboard)
    case peek(ClipItem)
    case move(ClipItem)
    case pro

    var id: String {
        switch self {
        case .settings: "settings"
        case .boards: "boards"
        case .boardAppearance(let board): "board-appearance-\(board.id.uuidString)"
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
                .onChange(of: model.selectedSourceAppBundleID) { _, _ in
                    Task { await model.search() }
                }
                .navigationTitle("Gancho")
                .navigationDestination(for: UUID.self) { id in
                    if let item = model.captures.first(where: { $0.id == id }) {
                        ClipDetailView(item: item)
                    }
                }
                .toolbar {
                    // Search keeps its bottom-bar slot (a bottom item alone
                    // would move the field back under the title), and the
                    // system paste control rides beside it: the one action the
                    // screen is for, within thumb reach, drawn by the OS so
                    // the one-tap consent stays the system's. Its own glass
                    // would double the control's green capsule, so the shared
                    // background steps aside.
                    DefaultToolbarItem(kind: .search, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        // One accessibility element: the bar item otherwise
                        // exposes a wrapper labelled by the control's visible
                        // text, and the label set here never reaches it.
                        PasteControlView { providers in model.ingest(providers: providers) }
                            .frame(width: 112, height: 44)
                            .accessibilityElement(children: .ignore)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("paste-control")
                            .accessibilityLabel(Text("Paste into Gancho"))
                    }
                    .sharedBackgroundVisibility(.hidden)
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
                    case .boardAppearance(let board):
                        BoardIdentityEditor(board: board) { colorHex, emoji in
                            await model.updateBoardIdentity(
                                board, colorHex: colorHex, emoji: emoji)
                        }
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
                        board: board
                    ) {
                        select(board: board.id)
                    }
                    .contextMenu {
                        if !board.isSystem {
                            Button("Customize board…") {
                                let current = model.boards.first { $0.id == board.id } ?? board
                                activeSheet = .boardAppearance(current)
                            }
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("board-rail")
    }

    private func railChip(
        _ label: Text, systemImage: String, isActive: Bool, board: Pinboard? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isActive {
                    Image(systemName: "checkmark").font(.caption)
                } else if let board {
                    BoardIdentityMark(board: board, size: 10)
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
        return HistoryFilterMenu(
            kindFilter: $model.kindFilter,
            selectedSourceAppBundleID: $model.selectedSourceAppBundleID,
            sourceApps: model.sourceApps)
    }

    private var hasActiveFilter: Bool {
        model.kindFilter != nil || model.selectedBoardID != nil
            || model.selectedSourceAppBundleID != nil
    }

    private func clearFilters() {
        model.kindFilter = nil
        model.selectedSourceAppBundleID = nil
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
                    "iOS apps can't watch the clipboard in the background — no app can. Capture with the Paste button, the share sheet from any app, or a Shortcut on your Action Button."
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
        await model.refreshSourceApps()
        await model.search()
    }

    /// The design's Pasteboard section: the status row the capture screen
    /// shows above history (see `PasteboardStatusRow`).
    private var pasteboardSection: some View {
        Section {
            PasteboardStatusRow()
                .listRowBackground(Color.clear)
                .listRowInsets(
                    EdgeInsets(
                        top: GanchoTokens.Spacing.xxs, leading: GanchoTokens.Spacing.xxs,
                        bottom: GanchoTokens.Spacing.xxs, trailing: GanchoTokens.Spacing.xxs))
        }
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
            .accessibilityElement(children: .contain)
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
        // The design's green Paste button, drawn by the system: it grants
        // one-time access on tap, with no "pasted from" banner.
        let config = UIPasteControl.Configuration()
        config.cornerStyle = .capsule
        config.displayMode = .iconAndLabel
        config.baseBackgroundColor = UIColor(GanchoTokens.Palette.accent)
        config.baseForegroundColor = .white
        let control = UIPasteControl(configuration: config)
        control.target = context.coordinator.target
        // The identifier and label assistive tech sees come from the SwiftUI
        // modifiers at the call site: SwiftUI writes its accessibility attributes
        // onto the hosted view (the UIKit-side label alone left VoiceOver reading
        // the system's "Paste"), which is also why an identifier on an enclosing
        // container would mask this control. The UIKit-side copies only keep the
        // control queryable if those modifiers are ever dropped.
        control.isAccessibilityElement = true
        control.accessibilityIdentifier = "paste-control"
        control.accessibilityLabel = String(localized: "Paste into Gancho")
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
