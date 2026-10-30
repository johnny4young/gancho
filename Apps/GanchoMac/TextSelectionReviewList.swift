import GanchoAppCore
import SwiftUI

/// One reorder/remove surface for temporary text reviews; never writes clips.
struct TextSelectionReviewList: View {
    @Binding var parts: [CombinedTextPart]
    let disabled: Bool
    /// Images whose recognized text the user chose to share. Nil where a
    /// review never offers recognized text.
    var approvedRecognizedText: Binding<Set<UUID>>?

    var body: some View {
        List {
            ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                HStack {
                    Text("Clip \(index + 1)").monospacedDigit()
                    if case .recognizedText = part.content, let approvedRecognizedText {
                        recognizedText(part, approved: approvedRecognizedText)
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

    @ViewBuilder
    private func recognizedText(
        _ part: CombinedTextPart, approved: Binding<Set<UUID>>
    )
        -> some View
    {
        if approved.wrappedValue.contains(part.id), let preview = part.preview {
            Image(systemName: "text.viewfinder")
                .accessibilityLabel(Text("Text recognized from an image"))
                .help(Text("Text recognized from an image"))
            Text(verbatim: preview).lineLimit(1).foregroundStyle(.secondary)
        } else {
            Text(status(part)).lineLimit(1).foregroundStyle(.secondary)
            Button("Use recognized text") { approved.wrappedValue.insert(part.id) }
                .accessibilityIdentifier("text-selection-use-recognized-text-button")
        }
    }

    private func status(_ part: CombinedTextPart) -> LocalizedStringKey {
        switch part.content {
        case .text: "Text ready"
        case .recognizedText: "Image with recognized text"
        case .incompatible: "Not a text clip"
        case .protected: "Protected clip"
        case .unavailable: "Clip unavailable"
        case .tooLarge: "Text exceeds the size limit"
        }
    }
}
