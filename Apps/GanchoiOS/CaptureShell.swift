import ClipboardCore
import GanchoDesign
import GanchoKit
import SwiftUI
import UIKit

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

/// What the iPhone stack and the iPad split view share around their lists:
/// the sheets, the Pro gate, foreground activation, pasteboard re-sensing and
/// widget deep links.
struct CaptureShell: ViewModifier {
    @Environment(IOSAppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    /// A single `.sheet(item:)`: stacking several `.sheet` modifiers on one
    /// view silently drops one of them.
    @Binding var activeSheet: CaptureSheet?
    /// Receives a deep link only once its clip resolved.
    let openClip: (ClipItem) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: $activeSheet) { sheet in
                CaptureSheetContent(sheet: sheet) { activeSheet = nil }
            }
            .onChange(of: model.proGateTick) { _, _ in
                // A free-tier limit was hit somewhere — show the Pro screen
                // rather than letting a vanishing note dead-end the user.
                activeSheet = .pro
            }
            .task { await activate() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await activate() }
            }
            // scenePhase can miss a return to the foreground; this cannot.
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.didBecomeActiveNotification)
            ) { _ in
                Task { await model.refreshHints() }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)
            ) { _ in
                Task { await model.refreshHints() }
            }
            .onChange(of: model.deepLinkClip, initial: true) { _, clip in
                guard let clip else { return }
                model.deepLinkClip = nil
                openClip(clip)
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
}

extension View {
    func captureShell(
        activeSheet: Binding<CaptureSheet?>, openClip: @escaping (ClipItem) -> Void
    ) -> some View {
        modifier(CaptureShell(activeSheet: activeSheet, openClip: openClip))
    }
}

private struct CaptureSheetContent: View {
    @Environment(IOSAppModel.self) private var model
    let sheet: CaptureSheet
    let close: () -> Void

    var body: some View {
        switch sheet {
        case .settings: IOSSettingsView()
        case .boards: BoardsHomeView()
        case .boardAppearance(let board):
            BoardIdentityEditor(board: board) { colorHex, emoji in
                await model.updateBoardIdentity(board, colorHex: colorHex, emoji: emoji)
            }
        case .peek(let clip):
            // Its own stack for a titled bar and an explicit Done, since
            // drag-to-dismiss isn't discoverable. The row resolves live so a
            // pin or an edit shows without reopening the peek.
            NavigationStack {
                ClipDetailView(item: model.liveClip(clip))
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done", action: close)
                        }
                    }
            }
        case .move(let clip): MoveToBoardSheet(item: clip)
        case .pro:
            NavigationStack {
                ProInfoView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done", action: close)
                        }
                    }
            }
        }
    }
}

/// The capture toolbar for both layouts. The iPhone keeps search and the
/// paste control in the bottom bar, within thumb reach; the iPad puts the
/// paste control in the history column's bar and filters from its sidebar.
struct CaptureToolbar: ToolbarContent {
    enum Layout { case phone, pad }

    let layout: Layout
    let model: IOSAppModel
    @Binding var activeSheet: CaptureSheet?

    var body: some ToolbarContent {
        if layout == .phone {
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
            // The control's own green capsule would double the shared glass.
            ToolbarItem(placement: .bottomBar) { pasteControl }
                .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .topBarTrailing) {
                HistoryFilterMenu(
                    kindFilter: Bindable(model).kindFilter,
                    selectedSourceAppBundleID: Bindable(model).selectedSourceAppBundleID,
                    sourceApps: model.sourceApps)
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) { pasteControl }
                .sharedBackgroundVisibility(.hidden)
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

    private var pasteControl: some View {
        // One accessibility element: the bar item otherwise exposes a wrapper
        // labelled by the control's visible text, and this label never reaches it.
        PasteControlView { providers in model.ingest(providers: providers) }
            .frame(width: 112, height: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("paste-control")
            .accessibilityLabel(Text("Paste into Gancho"))
    }
}

/// Swipe and long-press actions for one history row, the same on both layouts.
struct ClipRowActions: ViewModifier {
    let item: ClipItem
    let model: IOSAppModel
    let onMove: () -> Void

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    Task { await model.delete(item) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                pinButton.tint(.orange)
            }
            .swipeActions(edge: .leading) {
                Button {
                    Task { await model.copyToPasteboard(item) }
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .tint(.blue)
                Button(action: onMove) {
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
                if ClipSafeDelivery.isEligible(item) {
                    ShareLink(item: model.shareItem(for: item), preview: SharePreview("Gancho")) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("clip-share-action")
                }
                pinButton
                Divider()
                Button(role: .destructive) {
                    Task { await model.delete(item) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } preview: {
                preview
            }
    }

    private var pinButton: some View {
        Button {
            Task { await model.togglePin(item) }
        } label: {
            Label(
                item.isPinned ? "Unpin" : "Pin",
                systemImage: item.isPinned ? "pin.slash" : "pin")
        }
    }

    /// The image for image clips, otherwise the (masked-if-sensitive) text.
    @ViewBuilder private var preview: some View {
        if item.kind == .image, !ClipSafePresentation.requiresMasking(item),
            let thumbnail = model.thumbnails.cached(for: item.id)
        {
            thumbnail
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 300, maxHeight: 220)
        } else {
            Text(ClipSafePresentation.displayText(for: item))
                .font(item.kind == .code ? .body.monospaced() : .body)
                .padding()
                .frame(maxWidth: 300, alignment: .leading)
        }
    }
}

extension View {
    func clipRowActions(
        _ item: ClipItem, model: IOSAppModel, onMove: @escaping () -> Void
    ) -> some View {
        modifier(ClipRowActions(item: item, model: model, onMove: onMove))
    }
}

/// Shown only when the durable store failed to open — captures are running
/// in memory and will be lost on relaunch. Honest beats silent.
struct StorageWarningSection: View {
    var body: some View {
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
}

/// The status row the capture screen shows above history (see
/// `PasteboardStatusRow`); it also carries the transient save notes.
struct PasteboardSection: View {
    var body: some View {
        Section {
            PasteboardStatusRow()
                .listRowBackground(Color.clear)
                .listRowInsets(
                    EdgeInsets(
                        top: GanchoTokens.Spacing.xxs, leading: GanchoTokens.Spacing.xxs,
                        bottom: GanchoTokens.Spacing.xxs, trailing: GanchoTokens.Spacing.xxs))
        }
    }
}
