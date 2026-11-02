import AppKit
import ClipboardCore
import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// What a drop on the shelf carried.
enum NotchShelfDropContent {
    /// A clip dragged from Gancho's own rows, read back from the store.
    case clip(UUID)
    case payload(PasteboardCapture.Payload)
}

/// The boards and hover state one shelf renders.
@Observable
final class NotchShelfState {
    var boards: [Pinboard] = []
    var counts: [UUID: Int] = [:]
    var hovered: NotchShelfTarget?
    var mayBeImage = true
    @ObservationIgnored var frames: [NotchShelfTarget: CGRect] = [:]
}

/// A drop zone over the notch of every screen that has one, and at the top
/// center of the others while a drag is in progress. A drag that reaches a
/// zone opens the shelf below it.
final class NotchShelfController {
    /// False refuses every drag (Private Mode, a denylisted app in front).
    var isAllowed: @MainActor () -> Bool = { true }
    var boards: @MainActor () -> [Pinboard] = { [] }
    var counts: @MainActor () async -> [UUID: Int] = { [:] }
    var onDrop: @MainActor (NotchShelfTarget, NotchShelfDropContent) -> Void = { _, _ in }

    private var zones: [NotchShelfZone] = []
    private var watchTask: Task<Void, Never>?
    private var screenObserver: (any NSObjectProtocol)?
    private let dragPasteboard = NSPasteboard(name: .drag)

    func setEnabled(_ enabled: Bool) {
        if enabled, zones.isEmpty {
            rebuild()
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuild() }
            }
        } else if !enabled {
            watchTask?.cancel()
            watchTask = nil
            for zone in zones { zone.close() }
            zones = []
            screenObserver.map(NotificationCenter.default.removeObserver)
            screenObserver = nil
        }
    }

    func boardsChanged() {
        for zone in zones where zone.isExpanded { zone.reloadBoards() }
    }

    private func rebuild() {
        for zone in zones { zone.close() }
        zones = NSScreen.screens.map { NotchShelfZone(screen: $0, controller: self) }
        for zone in zones where !zone.showsOnlyWhileDragging {
            zone.orderFrontRegardless()
        }
        watchTask?.cancel()
        watchTask = zones.contains(where: \.showsOnlyWhileDragging) ? watchDrags() : nil
        #if DEBUG
            if CommandLine.arguments.contains("-ui-test-open-notch-shelf"),
                let zone = zones.first(where: { $0.screen == NSScreen.main }) ?? zones.first
            {
                zone.orderFrontRegardless()
                zone.expand(pinned: true)
            }
        #endif
    }

    /// Reads only the drag pasteboard's change count and the mouse button.
    private func watchDrags() -> Task<Void, Never> {
        Task { [weak self] in
            var watch = DragSessionWatch()
            while !Task.isCancelled {
                guard let self else { return }
                let dragging = watch.sample(
                    changeCount: dragPasteboard.changeCount,
                    isMouseDown: NSEvent.pressedMouseButtons & 1 != 0)
                let shows = dragging && isAllowed()
                for zone in zones where zone.showsOnlyWhileDragging && !zone.isPinned {
                    if shows, !zone.isVisible {
                        zone.orderFrontRegardless()
                    } else if !shows, zone.isVisible {
                        zone.collapse()
                        zone.orderOut(nil)
                    }
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }
}

/// One screen's zone, which grows into the shelf while a drag hovers it.
final class NotchShelfZone: NSPanel {
    let showsOnlyWhileDragging: Bool
    private(set) var isPinned = false
    private let zoneFrame: CGRect
    private let screenFrame: CGRect
    private let state = NotchShelfState()
    private weak var controller: NotchShelfController?
    private let shelfHost: NotchShelfHostingView
    private var countsTask: Task<Void, Never>?

    init(screen: NSScreen, controller: NotchShelfController) {
        let notch = NotchShelfGeometry.notch(
            in: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
            leftAreaWidth: screen.auxiliaryTopLeftArea?.width,
            rightAreaWidth: screen.auxiliaryTopRightArea?.width)
        let menuBarHeight = max(
            screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
        zoneFrame = NotchShelfGeometry.dropZone(
            in: screen.frame, notch: notch, menuBarHeight: menuBarHeight)
        screenFrame = screen.frame
        showsOnlyWhileDragging = notch == nil
        self.controller = controller
        shelfHost = NotchShelfHostingView(rootView: NotchShelfView(state: state))
        super.init(
            contentRect: zoneFrame, styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        setAccessibilityIdentifier("notch-shelf-zone")
        let dropView = NotchShelfDropView(zone: self, showsPill: showsOnlyWhileDragging)
        contentView = dropView
        shelfHost.isHidden = true
        shelfHost.appearance = NSAppearance(named: .darkAqua)
        dropView.addSubview(shelfHost)
        layoutZone()
    }

    private(set) var isExpanded = false

    func expand(pinned: Bool = false) {
        isPinned = isPinned || pinned
        guard !isExpanded, controller != nil else { return }
        isExpanded = true
        shelfHost.isHidden = false
        reloadBoards()
        hasShadow = true
    }

    /// Re-reads the boards and fits the window to the shelf.
    func reloadBoards() {
        guard isExpanded, let controller else { return }
        state.boards = Array(controller.boards().prefix(NotchShelfView.maxBoards))
        // Frames arrive only when a layout changes, so keep the ones still shown.
        let shown = Set(state.boards.map(\.id))
        state.frames = state.frames.filter { target, _ in
            if case .board(let id) = target { shown.contains(id) } else { true }
        }
        countsTask?.cancel()
        countsTask = Task { [weak self] in
            let counts = await controller.counts()
            guard !Task.isCancelled else { return }
            self?.state.counts = counts
        }
        shelfHost.layoutSubtreeIfNeeded()
        let size = shelfHost.fittingSize
        let shelf = NotchShelfGeometry.shelf(size: size, below: zoneFrame, in: screenFrame)
        let frame = zoneFrame.union(shelf)
        setFrame(frame, display: false)
        shelfHost.frame = shelf.offsetBy(dx: -frame.minX, dy: -frame.minY)
        layoutZone()
        invalidateShadow()
    }

    func collapse() {
        guard isExpanded, !isPinned else { return }
        isExpanded = false
        state.hovered = nil
        shelfHost.isHidden = true
        hasShadow = false
        setFrame(zoneFrame, display: false)
        layoutZone()
    }

    private func layoutZone() {
        (contentView as? NotchShelfDropView)?.joinsShelf = isExpanded
        (contentView as? NotchShelfDropView)?.zoneRect = zoneFrame.offsetBy(
            dx: -frame.minX, dy: -frame.minY)
    }

    /// Hover feedback, from the type list only.
    func dragMoved(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let types = Self.types(of: sender.draggingPasteboard)
        guard let controller, controller.isAllowed(), NotchShelfDrop.accepts(types: types) else {
            collapse()
            return []
        }
        expand()
        state.mayBeImage = NotchShelfDrop.mayBeImage(types: types)
        state.hovered = target(for: sender, types: types)
        // Copy, never move: a file dropped from Finder stays where it is.
        return state.hovered == nil ? [] : .copy
    }

    func dragExited() {
        state.hovered = nil
        collapse()
    }

    /// The first read of the drag's content, once it has landed on a target.
    func performDrop(_ sender: any NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        let types = Self.types(of: pasteboard)
        guard let controller, controller.isAllowed(), NotchShelfDrop.accepts(types: types),
            let target = target(for: sender, types: types)
        else { return false }
        let content: NotchShelfDropContent
        if types.contains(BoardDrop.clipReferenceType) {
            // Our own rows deliver their other types from the main actor, so
            // reading them here would deadlock; the id is enough.
            guard
                let data = pasteboard.data(forType: .init(BoardDrop.clipReferenceType)),
                let id = BoardDrop.clipID(from: data)
            else { return false }
            content = .clip(id)
        } else {
            guard let payload = NSPasteboardReader.payload(from: pasteboard),
                NotchShelfDrop.accepts(types: Self.types(of: pasteboard))
            else { return false }
            content = .payload(payload)
        }
        isPinned = false
        controller.onDrop(target, content)
        return true
    }

    private func target(for sender: any NSDraggingInfo, types: Set<String>) -> NotchShelfTarget? {
        var point = shelfHost.convert(sender.draggingLocation, from: nil)
        // SwiftUI frames are measured from the top.
        if !shelfHost.isFlipped { point.y = shelfHost.bounds.height - point.y }
        return NotchShelfDrop.target(at: point, in: state.frames, types: types)
    }

    private static func types(of pasteboard: NSPasteboard) -> Set<String> {
        Set((pasteboard.types ?? []).map(\.rawValue))
    }
}

/// Takes every drag over the zone and the shelf; the SwiftUI content below
/// only draws.
private final class NotchShelfDropView: NSView {
    private weak var zone: NotchShelfZone?
    private let showsPill: Bool
    var zoneRect: CGRect = .zero {
        didSet { needsDisplay = true }
    }
    /// Square corners while the shelf hangs below, so the two read as one.
    var joinsShelf = false {
        didSet { needsDisplay = true }
    }

    init(zone: NotchShelfZone, showsPill: Bool) {
        self.zone = zone
        self.showsPill = showsPill
        super.init(frame: .zero)
        registerForDraggedTypes(
            [
                .fileURL, .string, .URL, .png, .tiff, .rtf, .html,
                .init(BoardDrop.clipReferenceType), .init("public.jpeg"), .init("public.heic")
            ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func draw(_ dirtyRect: NSRect) {
        guard showsPill else {
            // A fully clear pixel lets the drag through to the menu bar below.
            NSColor.black.withAlphaComponent(0.01).setFill()
            zoneRect.fill()
            return
        }
        let radius = joinsShelf ? 0 : GanchoTokens.Radius.lg
        let path = NSBezierPath(roundedRect: zoneRect, xRadius: radius, yRadius: radius)
        // Square top corners: the strip hangs from the screen's top edge.
        path.append(NSBezierPath(rect: zoneRect.divided(atDistance: radius, from: .maxYEdge).slice))
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            path.fill()
        }
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        zone?.dragMoved(sender) ?? []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        zone?.dragMoved(sender) ?? []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        zone?.dragExited()
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        zone?.performDrop(sender) ?? false
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        zone?.collapse()
    }
}

/// Draws the shelf; hit-testing falls through to the drop view behind it.
private final class NotchShelfHostingView: NSHostingView<NotchShelfView> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
