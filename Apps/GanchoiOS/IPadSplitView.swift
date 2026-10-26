import GanchoDesign
import GanchoKit
import SwiftUI

/// iPad layout: boards, types and apps in the sidebar with the pasteboard
/// docked under them, history in the content column, the clip's detail on
/// the right. The same model and shell the iPhone stack drives.
struct IPadSplitView: View {
    @Environment(IOSAppModel.self) private var model
    @State private var selectedID: UUID?
    @State private var activeSheet: CaptureSheet?
    @State private var sidebarVisible = false
    private let keyboard = HardwareKeyboard.shared
    /// Bound to the history search field so ⌘F can focus it from a hardware
    /// keyboard (Magic Keyboard / Smart Keyboard Folio).
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            IPadSidebar(isVisible: $sidebarVisible)
        } content: {
            List(selection: $selectedID) {
                if model.storageIsEphemeral { StorageWarningSection() }
                // The docked card's status moves here with its Paste control.
                if !sidebarVisible { PasteboardSection() }
                historyRows
            }
            .overlay {
                // Gate on the storage warning so the empty-state doesn't cover
                // the "History isn't being saved" row when the store is ephemeral.
                if model.visibleClips.isEmpty && !model.storageIsEphemeral {
                    if model.isSearching {
                        ProgressView("Searching…")
                            .accessibilityIdentifier("search-progress-indicator")
                    } else if let failure = model.searchFailure {
                        SearchFailureNotice(failure: failure) { Task { await model.search() } }
                    } else {
                        ContentUnavailableView(
                            "No clips here", systemImage: "tray",
                            description: Text("Copy or share something to Gancho to see it here."))
                    }
                }
            }
            // A search/filter replaces the list; drop a selection that's no
            // longer in it so the detail pane's empty state is intentional,
            // not a ghost of a filtered-out clip.
            .onChange(of: model.visibleClips) { _, clips in
                if let id = selectedID, !clips.contains(where: { $0.id == id }) {
                    selectedID = nil
                }
            }
            .safeAreaInset(edge: .bottom) {
                if keyboard.isConnected { KeyboardLegend() }
            }
            .reuseSuggestionInset()
            .searchable(
                text: $model.query, placement: .toolbar, prompt: Text("Search your clipboard")
            )
            .searchFocused($searchFocused)
            .onChange(of: model.query) { _, _ in Task { await model.search() } }
            .navigationTitle(Text("History"))
            .navigationSubtitle(historySubtitle)
            .toolbar {
                CaptureToolbar(
                    layout: .pad, model: model, activeSheet: $activeSheet,
                    padShowsPaste: !sidebarVisible)
            }
            .refreshable { await model.forceSync() }
        } detail: {
            if let item = model.visibleClips.first(where: { $0.id == selectedID }) {
                // The id gives every clip fresh detail state: a revealed secret
                // or a draft must never carry over to the next selection.
                ClipDetailView(item: item, showsCopyShortcut: keyboard.isConnected)
                    .id(item.id)
            } else {
                Text("Select a clip")
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: model.kindGroup) { _, _ in Task { await model.search() } }
        .onChange(of: model.selectedBoardID) { _, _ in Task { await model.search() } }
        .onChange(of: model.selectedSourceAppBundleID) { _, _ in Task { await model.search() } }
        // Hardware-keyboard shortcuts for iPad: ⌘F focus search, ⌘⏎ copy the
        // selected clip, ⌘1–9 copy the Nth recent clip. ↑↓ row navigation comes
        // free from the List's selection binding.
        .background { keyboardCommands }
        .captureShell(activeSheet: $activeSheet) { clip in
            // Select it when the current filters show it; otherwise peek.
            if model.visibleClips.contains(where: { $0.id == clip.id }) {
                activeSheet = nil
                selectedID = clip.id
            } else {
                activeSheet = .peek(clip)
            }
        }
    }

    /// Pinned first, then the date sections, each with what it can vouch for;
    /// a board or a search lists flat.
    @ViewBuilder private var historyRows: some View {
        if model.isGroupedView {
            ForEach(model.sections) { group in
                Section {
                    ForEach(group.clips) { clipRow($0) }
                } header: {
                    SectionCountHeader(
                        title: group.section.title, count: model.headerCount(for: group))
                }
            }
        } else if !model.visibleClips.isEmpty {
            Section {
                ForEach(model.visibleClips) { clipRow($0) }
            } header: {
                SectionCountHeader(
                    title: model.query.isEmpty ? "History" : "Results", count: model.listCount)
            }
        }
    }

    /// The scope's total while nothing narrows it; otherwise what the list
    /// itself can vouch for.
    private var historySubtitle: Text {
        let narrowed =
            !model.query.isEmpty || model.kindFilter != nil || model.kindGroup != .all
            || model.selectedSourceAppBundleID != nil
        if !narrowed, let total = model.activeScopeCount { return Text("\(total) clips") }
        guard narrowed, let count = model.listCount else { return Text(verbatim: "") }
        return count.isAtLeast
            ? Text("At least \(count.value) clips") : Text("\(count.value) clips")
    }

    private func clipRow(_ item: ClipItem) -> some View {
        ClipCard(
            item: item, thumbnail: model.thumbnails.cached(for: item), showsStoredMask: true,
            currentDeviceName: model.currentDeviceName
        )
        .tag(item.id)
        .task(id: ClipContentVersion(item)) { await model.thumbnails.ensureLoaded(item) }
        .onAppear { Task { await model.loadMoreIfNeeded(item) } }
        .clipRowActions(item, model: model) { activeSheet = .move(item) }
    }

    /// Invisible buttons whose only job is to carry `.keyboardShortcut`s for a
    /// connected hardware keyboard. Kept off-screen (`background` + zero opacity)
    /// so they never affect layout or VoiceOver.
    @ViewBuilder private var keyboardCommands: some View {
        Group {
            Button(action: { searchFocused = true }, label: { Color.clear })
                .keyboardShortcut("f", modifiers: .command)
            Button(action: copySelected, label: { Color.clear })
                .keyboardShortcut(.return, modifiers: .command)
            ForEach(1...9, id: \.self) { n in
                Button(action: { copyClip(at: n - 1) }, label: { Color.clear })
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
            }
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    /// Copy the clip currently highlighted in the history column.
    private func copySelected() {
        guard let id = selectedID,
            let item = model.visibleClips.first(where: { $0.id == id })
        else { return }
        Task { await model.copyToPasteboard(item) }
    }

    /// Copy the Nth clip in the visible history (⌘1–9), selecting it too so the
    /// detail pane follows and the action is visible.
    private func copyClip(at index: Int) {
        let clips = model.visibleClips
        guard clips.indices.contains(index) else { return }
        selectedID = clips[index].id
        Task { await model.copyToPasteboard(clips[index]) }
    }
}
