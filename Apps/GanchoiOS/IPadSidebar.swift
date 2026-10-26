import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// The iPad sidebar: boards, type groups and source apps, each with its live
/// count and its active row washed in the accent, over the pasteboard card.
struct IPadSidebar: View {
    @Environment(IOSAppModel.self) private var model
    /// Whether this column is on screen, so the history toolbar carries Paste
    /// only while the docked card is hidden.
    @Binding var isVisible: Bool
    @State private var showNewBoard = false
    @State private var newBoardName = ""

    private var counts: ScopeCountSnapshot? { model.scopeCounts }

    var body: some View {
        List {
            Section("Boards") { boardRows }
            Section("Types") { typeRows }
            if !model.sourceApps.isEmpty {
                Section("Apps") { appRows }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Gancho")
        .safeAreaInset(edge: .bottom) {
            PasteboardStatusRow(docked: true)
                .padding(.horizontal, 10)
                .padding(.bottom, GanchoTokens.Spacing.xs)
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .task {
            model.tracksScopeCounts = true
            await model.refreshScopeCounts()
        }
        .alert("New board", isPresented: $showNewBoard) {
            TextField("Board name", text: $newBoardName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { model.createBoard(named: newBoardName) }
        }
    }

    @ViewBuilder private var boardRows: some View {
        row(
            Text("All clips"), id: "sidebar-board-row", isActive: model.selectedBoardID == nil,
            count: counts?.total
        ) {
            Image(systemName: "tray").foregroundStyle(.secondary)
        } action: {
            model.selectedBoardID = nil
        }
        ForEach(model.boards) { board in
            row(
                board.displayTitle, id: "sidebar-board-row",
                isActive: model.selectedBoardID == board.id,
                count: counts.map { $0.boards[board.id] ?? 0 }
            ) {
                BoardIdentityMark(board: board, size: 11)
            } action: {
                model.selectedBoardID = board.id
            }
        }
        Button {
            newBoardName = ""
            showNewBoard = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(GanchoTokens.Palette.accentInk)
                    .frame(width: 18)
                Text("New board…").font(.subheadline)
                Spacer(minLength: 4)
                if let usage = model.freeBoardUsage {
                    Text("\(usage.used) of \(usage.limit) · Free")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sidebar-new-board")
    }

    @ViewBuilder private var typeRows: some View {
        row(
            Text("All types"), id: "sidebar-type-row",
            isActive: model.kindGroup == .all && model.kindFilter == nil, count: nil
        ) {
            Image(systemName: "square.grid.2x2").foregroundStyle(.secondary)
        } action: {
            model.kindFilter = nil
            model.kindGroup = .all
        }
        ForEach(ClipKindFilter.allCases.filter { $0 != .all }) { group in
            if let kind = group.tintKind {
                row(
                    group.sidebarTitle, id: "sidebar-type-row", isActive: model.kindGroup == group,
                    count: counts.map { group.count(in: $0.kinds) }
                ) {
                    Image(systemName: kind.symbolName)
                        .foregroundStyle(
                            ReadableInk(base: GanchoTokens.Palette.kindTint(for: kind)))
                } action: {
                    model.kindGroup = group
                }
            }
        }
    }

    @ViewBuilder private var appRows: some View {
        row(
            Text("All apps"), id: "source-app-all",
            isActive: model.selectedSourceAppBundleID == nil, count: nil
        ) {
            Image(systemName: "square.grid.2x2").foregroundStyle(.secondary)
        } action: {
            model.selectedSourceAppBundleID = nil
        }
        ForEach(model.sourceApps) { app in
            row(
                Text(verbatim: SourceApp.fallbackName(forBundleID: app.bundleID)),
                id: "source-app-\(app.bundleID)",
                isActive: model.selectedSourceAppBundleID == app.bundleID, count: app.clipCount
            ) {
                SourceAppTile(bundleID: app.bundleID, size: 16)
            } action: {
                model.selectedSourceAppBundleID = app.bundleID
            }
        }
    }

    /// One sidebar row. The active one takes the accent wash and a heavier
    /// name, and says so to VoiceOver: never a bar, never colour alone.
    private func row<Icon: View>(
        _ title: Text, id: String, isActive: Bool, count: Int?,
        @ViewBuilder icon: () -> Icon, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon().frame(width: 18)
                title
                    .font(.subheadline.weight(isActive ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let count {
                    Text(count, format: .number)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            isActive
                ? RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
                    .fill(GanchoTokens.Palette.accent.opacity(0.16))
                    .padding(.horizontal, 10)
                : nil
        )
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

extension ClipKindFilter {
    /// The sidebar's name for a type group, as the Mac's type rail names it.
    fileprivate var sidebarTitle: Text {
        switch self {
        case .all: Text("All types")
        case .links: Text("Links")
        case .code: Text("Code")
        case .colors: Text("Colors")
        case .images: Text("Images")
        case .secrets: Text("Secrets")
        }
    }
}
