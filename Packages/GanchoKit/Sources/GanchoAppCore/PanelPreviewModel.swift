import Foundation
import GanchoKit
import Observation

/// The text and editing capability the macOS peek may render for one clip.
///
/// The model returns a metadata-only fallback whenever the requested clip does
/// not match its current selection, so an asynchronous load can never flash a
/// previous clip's body into a newly selected row.
public struct PanelPreviewPresentation: Sendable, Equatable {
    public let text: String
    public let isTextEditable: Bool
}

/// Owns selected-clip preview loading for the macOS panel.
///
/// `ClipPreviewLoader` remains the shared content privacy boundary. This model
/// adds the panel-specific identity, cancellation, stale-result, and editability
/// policy that does not belong in SwiftUI.
@MainActor @Observable public final class PanelPreviewModel {
    public private(set) var selectedItemID: UUID?
    public private(set) var text = ""
    public private(set) var isTextEditable = false

    @ObservationIgnored private let loader: ClipPreviewLoader
    @ObservationIgnored private var loadGeneration: UInt64 = 0

    public init(loader: ClipPreviewLoader = ClipPreviewLoader()) {
        self.loader = loader
    }

    /// Resolves a presentation for the view's current selection.
    ///
    /// A mismatched id deliberately ignores the model's stored text. SwiftUI can
    /// render immediately after selection changes while the new task is still
    /// debouncing without exposing the previously selected clip.
    public func presentation(for item: ClipItem) -> PanelPreviewPresentation {
        guard selectedItemID == item.id else {
            return Self.metadataPresentation(for: item)
        }
        return PanelPreviewPresentation(text: text, isTextEditable: isTextEditable)
    }

    /// Loads one selected clip and applies its result only while that exact
    /// request remains current.
    public func load(
        _ item: ClipItem?,
        loadContent: @Sendable (UUID) async throws -> ClipContent?
    ) async {
        loadGeneration &+= 1
        let generation = loadGeneration

        guard let item else {
            selectedItemID = nil
            text = ""
            isTextEditable = false
            return
        }

        let metadata = Self.metadataPresentation(for: item)
        selectedItemID = item.id
        text = metadata.text
        isTextEditable = false

        // These kinds render from their dedicated thumbnail/file UI. Reading a
        // blob merely to reproduce the list preview would add selection latency.
        guard item.kind != .image, item.kind != .fileReference else { return }

        let payload = await loader.load(item, loadContent: loadContent)
        guard
            !Task.isCancelled,
            loadGeneration == generation,
            selectedItemID == item.id
        else { return }

        switch payload {
        case .masked(let loadedText), .text(let loadedText):
            text = loadedText
            isTextEditable =
                !ClipSafePresentation.requiresMasking(item)
                && item.kind.allowsTextEditing
        case .binary, .fileReferences, .unavailable:
            break
        }
    }

    private static func metadataPresentation(for item: ClipItem) -> PanelPreviewPresentation {
        PanelPreviewPresentation(
            text: ClipSafePresentation.requiresMasking(item)
                ? ClipSafePresentation.masked : item.preview,
            isTextEditable: false)
    }
}
