import ClipboardCore
import GanchoAI
import GanchoKit
import ImageIO
import Observation
import SwiftUI

/// What the share sheet will save and the choices made on it. The deposit is
/// the same sealed inbox file as an instant save, carrying the choices.
@MainActor @Observable final class ShareSheetModel {
    let captures: [SharedInbox.PreparedCapture]
    let boards: [Pinboard]
    var title: String
    var selectedBoardIDs: Set<UUID> = []
    var newBoardName: String?
    var isPinned = false
    var isSaving = false
    var saveFailed = false
    /// A small decode of the first image, so the preview never holds the full
    /// bitmap inside the extension's memory ceiling.
    let thumbnail: Image?

    private let inbox: SharedInbox

    init(
        captures: [SharedInbox.PreparedCapture], suggestedTitle: String?, boards: [Pinboard],
        inbox: SharedInbox
    ) {
        self.captures = captures
        self.boards = boards
        self.inbox = inbox
        title = suggestedTitle ?? ""
        thumbnail = captures.first.flatMap(Self.thumbnail(for:))
        isProtected = captures.first.map(Self.isProtected) ?? false
    }

    private static func isProtected(_ prepared: SharedInbox.PreparedCapture) -> Bool {
        if ClipSafePresentation.requiresMasking(kind: prepared.kind ?? .text, isSensitive: false) {
            return true
        }
        // The preview shows the start; the app checks the whole text on drain.
        return prepared.capture.textRepresentation.map {
            SensitiveDataDetector().detect(String($0.prefix(16_000))) != nil
        } ?? false
    }

    private static func thumbnail(for prepared: SharedInbox.PreparedCapture) -> Image? {
        guard case .image(let data, _) = prepared.capture.payload,
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 108,
                    kCGImageSourceCreateThumbnailWithTransform: true
                ] as CFDictionary)
        else { return nil }
        return Image(decorative: image, scale: 3)
    }

    /// A secret the extension can see: masked kinds, and text the detector
    /// flags. It previews masked and takes no title.
    let isProtected: Bool

    /// The title applies to a single capture; several share one set of boards.
    var offersTitle: Bool { captures.count == 1 && !isProtected }

    var choices: SharedInbox.ShareChoices {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return SharedInbox.ShareChoices(
            title: offersTitle && !trimmed.isEmpty ? trimmed : nil,
            boardIDs: boards.map(\.id).filter(selectedBoardIDs.contains),
            newBoardName: newBoardName, isPinned: isPinned)
    }

    func toggle(_ board: Pinboard) {
        if selectedBoardIDs.remove(board.id) == nil { selectedBoardIDs.insert(board.id) }
    }

    /// True when every capture landed in the inbox. Sealing and writing run
    /// off the main thread, so a large image never freezes the sheet.
    func save() async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        let inbox = inbox
        let prepared = captures.map { capture in
            var prepared = capture
            prepared.choices = choices
            return prepared
        }
        let saved = await Task.detached {
            prepared.filter { (try? inbox.deposit($0)) != nil }.count
        }.value
        saveFailed = saved < captures.count
        return !saveFailed
    }
}
