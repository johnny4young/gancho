import AppKit
import ClipboardCore
import GanchoDesign
import GanchoKit

/// Colours taken from image clips, and the colour hero's per-format copy.
extension AppModel {
    /// Saves a colour picked from an image as a colour clip, through the same
    /// ingestion as a copy, so Private Mode and every capture rule still apply.
    func saveColorClip(_ color: ColorValue) {
        Task { @MainActor in
            guard await saveManualText(color.hex) else {
                toasts.show(GanchoToast(message: "Couldn’t save the color.", style: .warning))
                return
            }
            toasts.show(GanchoToast(message: "Saved \(color.hex) as a color clip"))
        }
    }

    /// The exact pixel of the full-resolution image under a point of the
    /// peek's fitted preview; nil for a masked clip or a point off the image.
    func sampleColor(
        of item: ClipItem, at point: CGPoint, in viewSize: CGSize
    ) async
        -> ColorValue?
    {
        guard item.kind == .image, !ClipSafePresentation.requiresMasking(item),
            !preferences.isPrivateModePaused,
            case .binary(let data, _)? = try? await store.content(for: item.id)
        else { return nil }
        return await Task.detached(priority: .userInitiated) {
            guard let size = ImageColors.orientedSize(of: data),
                let pixel = ImageColors.pixel(at: point, in: viewSize, imageSize: size)
            else { return nil }
            return ImageColors.color(atPixel: pixel, in: data)
        }.value
    }

    /// One format line of the colour hero, copied with the same guard as OCR text.
    func copyColorFormat(_ value: String, label: String) {
        writeManualText(value)
        toasts.show(GanchoToast(message: "Copied \(label)"))
    }
}
