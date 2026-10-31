import ClipboardCore
import GanchoAI
import GanchoAppCore
import GanchoKit
import UIKit

extension IOSAppModel {
    func canReadImageText(_ item: ClipItem) -> Bool {
        store is any ImageTextReading && item.kind == .image
            && !ClipSafePresentation.requiresMasking(item)
            && (item.expiresAt.map { $0 > .now } ?? true)
    }

    /// Reads the image when its clip opens: on device, held in memory only,
    /// and never copied without a tap.
    func readImageText(_ item: ClipItem) {
        guard canReadImageText(item), let reader = store as? any ImageTextReading else {
            manualOCR.cancel()
            return
        }
        if manualOCR.itemID == item.id,
            manualOCR.state == .recognizing || manualOCR.state == .ready
        {
            return
        }
        let detector = SensitiveDataDetector()
        manualOCR.start(
            itemID: item.id,
            recognize: {
                try await ManualImageTextService().result(
                    for: item.id, store: reader, freshRegions: true)
            },
            isAllowed: { (try? await reader.permitsImageText(id: item.id, now: .now)) == true },
            isSensitive: { detector.detect($0) != nil },
            autoCopy: false,
            clipboardRevision: { UIPasteboard.general.changeCount },
            copy: { _ in },
            didFinish: { _ in })
    }

    /// Ends the read for a clip that closed; a newer clip's read is left alone.
    func endImageText(for id: UUID) {
        if manualOCR.itemID == id { manualOCR.cancel() }
    }

    /// Copies recognized text after the source is checked again.
    func copyRecognizedText(_ text: String) async -> Bool {
        guard let validated = await manualOCR.reviewedText(text) else { return false }
        UIPasteboard.general.string = validated
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        return true
    }

    func saveRecognizedLines(_ text: String) async -> Bool {
        guard let validated = await manualOCR.reviewedText(text) else { return false }
        return await saveTextAsClip(validated)
    }
}
