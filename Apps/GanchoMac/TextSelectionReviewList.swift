import GanchoAppCore
import SwiftUI

/// What a review lets the user share from each image.
struct ImageReviewChoices {
    var approvedText: Binding<Set<UUID>>
    var sharedImages: Set<UUID>
    var preparingImages: Set<UUID>
    var shareImage: (UUID) -> Void
}

/// One reorder/remove surface for temporary text reviews; never writes clips.
struct TextSelectionReviewList: View {
    @Binding var parts: [CombinedTextPart]
    let disabled: Bool
    /// Nil where a review never offers more than text.
    var imageChoices: ImageReviewChoices?

    var body: some View {
        List {
            ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                HStack {
                    Text("Clip \(index + 1)").monospacedDigit()
                    if part.isImage, let imageChoices {
                        imageRow(part, imageChoices)
                    } else if let preview = part.preview {
                        Text(verbatim: preview).lineLimit(1).foregroundStyle(
                            .secondary)
                    } else {
                        Text(status(part)).lineLimit(1).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Move up", systemImage: "arrow.up") { parts.swapAt(index, index - 1) }
                        .labelStyle(.iconOnly).disabled(index == 0)
                        .accessibilityIdentifier("text-selection-move-up-button")
                    Button("Move down", systemImage: "arrow.down") {
                        parts.swapAt(index, index + 1)
                    }
                    .labelStyle(.iconOnly).disabled(index + 1 == parts.count)
                    .accessibilityIdentifier("text-selection-move-down-button")
                    Button("Remove", systemImage: "minus.circle") { parts.remove(at: index) }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("text-selection-remove-button")
                }
            }
        }.frame(height: 140).disabled(disabled)
    }

    /// Text and pixels are chosen separately; choosing one never adds the other.
    @ViewBuilder
    private func imageRow(_ part: CombinedTextPart, _ choices: ImageReviewChoices) -> some View {
        if choices.approvedText.wrappedValue.contains(part.id), let preview = part.preview {
            Image(systemName: "text.viewfinder")
                .accessibilityLabel(Text("Text recognized from an image"))
                .help(Text("Text recognized from an image"))
            Text(verbatim: preview).lineLimit(1).foregroundStyle(.secondary)
        } else {
            Text(status(part)).lineLimit(1).foregroundStyle(.secondary)
            if case .recognizedText = part.content {
                Button("Use recognized text") { choices.approvedText.wrappedValue.insert(part.id) }
                    .accessibilityIdentifier("text-selection-use-recognized-text-button")
            }
        }
        if choices.sharedImages.contains(part.id) {
            Image(systemName: "photo")
                .accessibilityLabel(Text("Image shared"))
                .help(Text("Image shared"))
        } else if choices.preparingImages.contains(part.id) {
            ProgressView().controlSize(.small)
        } else {
            Button("Share image") { choices.shareImage(part.id) }
                .accessibilityIdentifier("text-selection-share-image-button")
        }
    }

    private func status(_ part: CombinedTextPart) -> LocalizedStringKey {
        switch part.content {
        case .text: "Text ready"
        case .recognizedText: "Image with recognized text"
        case .image: "Image without recognized text"
        case .incompatible: "Not a text clip"
        case .protected: "Protected clip"
        case .unavailable: "Clip unavailable"
        case .tooLarge: "Text exceeds the size limit"
        }
    }
}

extension CombinedTextPart {
    fileprivate var isImage: Bool {
        switch content {
        case .recognizedText, .image: true
        case .text, .unavailable, .incompatible, .protected, .tooLarge: false
        }
    }
}
