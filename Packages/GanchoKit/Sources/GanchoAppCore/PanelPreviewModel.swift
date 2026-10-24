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

/// A selected revision and the store event that requires rereading it. A
/// mutation elsewhere can leave the selected revision unchanged, so the view
/// must still reload a preview invalidated by that event.
public struct PanelPreviewRequestKey: Equatable, Sendable {
    /// Persisted selection identity; contains no loaded preview text.
    public let version: ClipContentVersion?
    /// Changes when a relevant mutation requires a fresh preview read.
    public let storeRevision: Int

    /// Binds the view's selected item to the latest handled store event.
    public init(item: ClipItem?, storeRevision: Int) {
        version = item.map(ClipContentVersion.init)
        self.storeRevision = storeRevision
    }
}

/// Owns selected-clip preview loading for the macOS panel.
///
/// `ClipPreviewLoader` remains the shared content privacy boundary. This model
/// adds the panel-specific identity, cancellation, stale-result, and editability
/// policy that does not belong in SwiftUI.
@MainActor @Observable public final class PanelPreviewModel {
    private var selectedVersion: ClipContentVersion?
    private var text = ""
    private var isTextEditable = false

    @ObservationIgnored private let loader = ClipPreviewLoader()
    @ObservationIgnored private var loadGeneration: UInt64 = 0

    public init() {}

    /// Forgets loaded text and invalidates an in-flight read synchronously.
    /// The shell reloads through a fresh ``PanelPreviewRequestKey`` afterwards.
    public func invalidate() {
        loadGeneration &+= 1
        selectedVersion = nil
        text = ""
        isTextEditable = false
    }

    /// Resolves a presentation for the view's current selection.
    ///
    /// A mismatched id deliberately ignores the model's stored text. SwiftUI can
    /// render immediately after selection changes while the new task is still
    /// debouncing without exposing the previously selected clip.
    public func presentation(for item: ClipItem) -> PanelPreviewPresentation {
        guard !ClipSafePresentation.requiresMasking(item),
            selectedVersion == ClipContentVersion(item)
        else {
            return Self.metadataPresentation(for: item)
        }
        return PanelPreviewPresentation(text: text, isTextEditable: isTextEditable)
    }

    /// Loads one selected clip and applies its result only while that exact
    /// request remains current. Cancellation is checked before durable content
    /// access and again before applying the result. `loadMetadata` re-reads the
    /// persisted row afterwards, so an edit or protection change during the
    /// read never publishes text under the selection's older revision.
    public func load(
        _ item: ClipItem?,
        loadMetadata: (@Sendable (UUID) async throws -> ClipItem?)? = nil,
        loadContent: @Sendable (UUID) async throws -> ClipContent?
    ) async {
        loadGeneration &+= 1
        let generation = loadGeneration

        guard let item else {
            selectedVersion = nil
            text = ""
            isTextEditable = false
            return
        }

        let metadata = Self.metadataPresentation(for: item)
        selectedVersion = ClipContentVersion(item)
        text = metadata.text
        isTextEditable = false

        // These kinds render from their dedicated thumbnail/file UI. Reading a
        // blob merely to reproduce the list preview would add selection latency.
        guard item.kind != .image, item.kind != .fileReference else { return }
        guard !Task.isCancelled else { return }

        let payload = await loader.load(item, loadContent: loadContent)
        if let loadMetadata {
            guard let current = try? await loadMetadata(item.id),
                ClipContentVersion(current) == ClipContentVersion(item)
            else { return }
        }
        guard
            !Task.isCancelled,
            loadGeneration == generation,
            selectedVersion == ClipContentVersion(item)
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
