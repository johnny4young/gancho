import GanchoDesign
import GanchoKit
import SwiftUI

/// iPad layout: kind filters in the sidebar, history in the content column,
/// per-clip detail on the right — the same model the iPhone stack drives.
struct IPadSplitView: View {
    @Environment(IOSAppModel.self) private var model
    @State private var selectedID: UUID?
    /// Bound to the history search field so ⌘F can focus it from a hardware
    /// keyboard (Magic Keyboard / Smart Keyboard Folio).
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.kindFilter) {
                Section("Boards") {
                    boardRow(
                        label: Text("All clips"), symbol: "tray.full",
                        isActive: model.selectedBoardID == nil
                    ) {
                        model.selectedBoardID = nil
                    }
                    ForEach(model.boards) { board in
                        boardRow(
                            label: board.isSystem ? Text("Favorites") : Text(verbatim: board.name),
                            symbol: board.sfSymbol, isActive: model.selectedBoardID == board.id
                        ) {
                            model.selectedBoardID = board.id
                        }
                    }
                }
                Section("Types") {
                    Label("All types", systemImage: "tray.full")
                        .tag(ClipContentKind?.none)
                    ForEach(ClipContentKind.allCases, id: \.self) { kind in
                        Label(LocalizedStringKey(kind.rawValue), systemImage: kind.symbolName)
                            .tag(ClipContentKind?.some(kind))
                    }
                }
                if !model.sourceApps.isEmpty {
                    Section("Apps") {
                        sourceAppRow(nil)
                        ForEach(model.sourceApps) { sourceAppRow($0) }
                    }
                }
            }
            .navigationTitle("Gancho")
            .onChange(of: model.kindFilter) { _, _ in Task { await model.search() } }
            .onChange(of: model.selectedBoardID) { _, _ in Task { await model.search() } }
            .onChange(of: model.selectedSourceAppBundleID) { _, _ in
                Task { await model.search() }
            }
        } content: {
            List(selection: $selectedID) {
                if model.storageIsEphemeral { storageWarningSection }
                ForEach(model.captures) { item in
                    ClipCard(item: item).tag(item.id)
                }
            }
            .overlay {
                // Gate on the storage warning so the empty-state doesn't cover
                // the "History isn't being saved" row when the store is ephemeral.
                if model.captures.isEmpty && !model.storageIsEphemeral {
                    ContentUnavailableView(
                        "No clips here", systemImage: "tray",
                        description: Text("Copy or share something to Gancho to see it here."))
                }
            }
            // A search/filter replaces `captures`; drop a selection that's no
            // longer in the list so the detail pane's empty state is intentional,
            // not a ghost of a filtered-out clip.
            .onChange(of: model.captures) { _, clips in
                if let id = selectedID, !clips.contains(where: { $0.id == id }) {
                    selectedID = nil
                }
            }
            .searchable(text: $model.query, prompt: Text("Search your clipboard"))
            .searchFocused($searchFocused)
            .onChange(of: model.query) { _, _ in Task { await model.search() } }
            .navigationTitle(Text("History"))
            .refreshable { await model.forceSync() }
        } detail: {
            if let item = model.captures.first(where: { $0.id == selectedID }) {
                // ClipDetailView is shaped for the iPhone peek sheet (full-width
                // action row, edge-to-edge text). On a wide iPad pane that runs
                // the buttons and lines too long, so cap it to a readable column
                // and centre it instead of stretching to the pane edge.
                ClipDetailView(item: item)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Text("Select a clip")
                    .foregroundStyle(.secondary)
            }
        }
        // Hardware-keyboard shortcuts for iPad: ⌘F focus search, ⌘⏎ copy the
        // selected clip, ⌘1–9 copy the Nth recent clip. ↑↓ row navigation comes
        // free from the List's selection binding.
        .background { keyboardCommands }
        .task {
            await model.refreshHints()
            await model.drainSharedInbox()
            await model.refreshBoards()
            await model.refreshSourceApps()
            await model.search()
        }
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
            let item = model.captures.first(where: { $0.id == id })
        else { return }
        Task { await model.copyToPasteboard(item) }
    }

    /// Copy the Nth clip in the visible history (⌘1–9), selecting it too so the
    /// detail pane follows and the action is visible.
    private func copyClip(at index: Int) {
        let clips = model.captures
        guard clips.indices.contains(index) else { return }
        selectedID = clips[index].id
        Task { await model.copyToPasteboard(clips[index]) }
    }

    /// Shown when iPad is also on the in-memory fallback. The iPhone stack has
    /// the same warning; keep the split view honest too.
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

    /// A board row in the sidebar: glyph + name, with a checkmark on the active
    /// board. Favorites shows its localized label.
    private func boardRow(
        label: Text, symbol: String, isActive: Bool, action: @escaping () -> Void
    )
        -> some View
    {
        Button(action: action) {
            HStack {
                Label {
                    label
                } icon: {
                    Image(systemName: symbol)
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func sourceAppRow(_ sourceApp: ClipSourceApp?) -> some View {
        let bundleID = sourceApp?.bundleID
        let selected = model.selectedSourceAppBundleID == bundleID
        return Button {
            model.selectedSourceAppBundleID = bundleID
        } label: {
            HStack {
                Label {
                    if let bundleID {
                        Text(verbatim: SourceApp.fallbackName(forBundleID: bundleID))
                    } else {
                        Text("All apps")
                    }
                } icon: {
                    Image(systemName: bundleID == nil ? "square.grid.2x2" : "app.dashed")
                }
                Spacer()
                if let sourceApp {
                    Text(verbatim: "\(sourceApp.clipCount)").foregroundStyle(.secondary)
                }
                if selected { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(bundleID.map { "source-app-\($0)" } ?? "source-app-all")
    }
}
