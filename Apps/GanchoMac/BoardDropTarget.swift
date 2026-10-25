import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI
import UniformTypeIdentifiers

/// How a board looks under a dragged clip: a green ring and a 1.04 lift while
/// it hovers, a pulse once the clip is filed. Under Reduce Motion the ring
/// stays and nothing scales.
struct BoardDropFeedback<Ring: InsettableShape>: ViewModifier {
    let isTargeted: Bool
    let pulses: Bool
    let ring: Ring
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                ring.strokeBorder(GanchoTokens.Palette.accent, lineWidth: 2)
                    .opacity(isTargeted ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .scaleEffect(!reduceMotion && (isTargeted || pulses) ? 1.04 : 1)
            .animation(GanchoMotion.smooth(reduceMotion: reduceMotion), value: isTargeted)
            .animation(GanchoMotion.smooth(reduceMotion: reduceMotion), value: pulses)
    }
}

/// A board (panel rail chip or Library sidebar row) that files a clip
/// dragged inside the app.
struct BoardDropTarget<Ring: InsettableShape>: ViewModifier {
    let board: Pinboard
    let ring: Ring
    @Environment(AppModel.self) private var model
    @State private var isTargeted = false
    @State private var pulses = false

    func body(content: Content) -> some View {
        content
            .modifier(BoardDropFeedback(isTargeted: isTargeted, pulses: pulses, ring: ring))
            .onDrop(of: [.ganchoClipReference], isTargeted: $isTargeted) { providers in
                guard let provider = providers.first else { return false }
                BoardDropLoader.loadClipID(from: provider) { id in
                    guard await model.drop(clipID: id, onBoard: board) else { return }
                    pulses = true
                    try? await Task.sleep(for: .milliseconds(220))
                    pulses = false
                }
                return true
            }
            #if DEBUG
                .task(id: model.boards.first { !$0.isSystem }?.id) {
                    // Snapshot fixtures render the hover state without a live drag.
                    if CommandLine.arguments.contains("-ui-test-target-first-board"),
                        model.boards.first(where: { !$0.isSystem })?.id == board.id
                    {
                        isTargeted = true
                    }
                }
            #endif
    }
}

enum BoardDropLoader {
    /// Reads the dragged clip's id, then hands it to `handle` on the main actor.
    static func loadClipID(
        from provider: NSItemProvider, then handle: @escaping @MainActor (UUID) async -> Void
    ) {
        _ = provider.loadDataRepresentation(
            forTypeIdentifier: UTType.ganchoClipReference.identifier
        ) { data, _ in
            guard let id = data.flatMap(BoardDrop.clipID(from:)) else { return }
            Task { @MainActor in await handle(id) }
        }
    }
}

extension View {
    func boardDropTarget(_ board: Pinboard, ring: some InsettableShape) -> some View {
        modifier(BoardDropTarget(board: board, ring: ring))
    }
}
