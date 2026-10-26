import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

extension View {
    /// Lifts the clip into another app beside Gancho. Bytes load only when a
    /// drop target asks, through the same safe delivery as Share; a masked or
    /// expired clip is no drag source at all.
    @ViewBuilder
    func clipDragSource(_ item: ClipItem, model: IOSAppModel, enabled: Bool = true) -> some View {
        if enabled, ClipDragPayload.liftsNow(item) {
            draggable(model.shareItem(for: item)) { ClipDragPreview(kind: item.kind) }
        } else {
            self
        }
    }
}

/// What the finger carries: the kind, never the content.
private struct ClipDragPreview: View {
    let kind: ClipContentKind

    var body: some View {
        let tint = GanchoTokens.Palette.kindTint(for: kind)
        Label {
            Text(kind.cardName)
        } icon: {
            Image(systemName: kind.symbolName)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, GanchoTokens.Spacing.sm)
        .padding(.vertical, GanchoTokens.Spacing.xs)
        .ganchoTintedPill(tint, wash: 0.16)
        .background(.background, in: Capsule())
    }
}
