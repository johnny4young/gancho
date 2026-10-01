import GanchoAppCore
import SwiftUI

/// One reorder/remove surface for temporary text reviews; never writes clips.
struct TextSelectionReviewList: View {
    @Binding var parts: [CombinedTextPart]
    let disabled: Bool

    var body: some View {
        List {
            ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                HStack {
                    Text("Clip \(index + 1)").monospacedDigit()
                    if let preview = part.preview {
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

    private func status(_ part: CombinedTextPart) -> LocalizedStringKey {
        switch part.content {
        case .text: "Text ready"
        case .incompatible: "Not a text clip"
        case .protected: "Protected clip"
        case .unavailable: "Clip unavailable"
        case .tooLarge: "Text exceeds the size limit"
        }
    }
}
