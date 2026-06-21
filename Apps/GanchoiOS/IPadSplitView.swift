import GanchoDesign
import GanchoKit
import SwiftUI

/// iPad layout: kind filters in the sidebar, history in the content column,
/// per-clip detail on the right — the same model the iPhone stack drives.
struct IPadSplitView: View {
    @Environment(IOSAppModel.self) private var model
    @State private var selectedID: UUID?

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
            }
            .navigationTitle("Gancho")
            .onChange(of: model.kindFilter) { _, _ in Task { await model.search() } }
            .onChange(of: model.selectedBoardID) { _, _ in Task { await model.search() } }
        } content: {
            List(model.captures, selection: $selectedID) { item in
                ClipCard(item: item).tag(item.id)
            }
            .searchable(text: $model.query, prompt: Text("Search your clipboard"))
            .onChange(of: model.query) { _, _ in Task { await model.search() } }
            .navigationTitle(Text("History"))
            .refreshable { await model.forceSync() }
        } detail: {
            if let item = model.captures.first(where: { $0.id == selectedID }) {
                ClipDetailView(item: item)
            } else {
                Text("Select a clip")
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            await model.refreshHints()
            await model.drainSharedInbox()
            await model.refreshBoards()
            await model.search()
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
}
