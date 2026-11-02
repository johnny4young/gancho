import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

extension ClipPeek {
    /// A secret gets its own hero, except while previews are hidden (sharing,
    /// private mode), which keeps the plain mask and no reveal.
    var showsSecretHero: Bool {
        ClipSafePresentation.requiresMasking(item) && !model.previewsHidden
    }

    var secretSection: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.sm) {
            PeekSecretHero(
                item: item,
                lifetime: SecretLifetime(
                    item: item, lifetime: model.retentionPolicy.sensitiveLifetime),
                revealedText: secretText, reveal: secretReveal)
            FlowLayout(spacing: GanchoTokens.Spacing.xs) {
                ForEach(Array(secretActions.enumerated()), id: \.element.id) { offset, action in
                    actionButton(action, index: secretStartIndex + offset, style: .chip)
                }
            }
            Spacer(minLength: 0)
        }
    }

    var secretStartIndex: Int {
        dockActions.count
    }

    /// A secret's timed reveal and Delete now; no reveal while the screen is shared.
    var secretActions: [PeekAction] {
        guard showsSecretHero else { return [] }
        let reveal =
            secretText == nil
            ? PeekAction(id: "peek-reveal-button", title: "Reveal for 10 s", symbol: "eye") {
                startSecretReveal()
            }
            : PeekAction(id: "peek-hide-button", title: "Hide", symbol: "eye.slash") {
                endSecretReveal()
            }
        let delete = PeekAction(
            id: "peek-delete-now", title: "Delete now", symbol: "trash", isDestructive: true
        ) { model.delete(item) }
        let canReveal = item.kind != .image && (model.secretRevealAllowed || secretText != nil)
        return canReveal ? [reveal, delete] : [delete]
    }

    func startSecretReveal() {
        let request = secretHideCount
        Task {
            guard let text = await model.revealedSecretText(item), request == secretHideCount,
                model.secretRevealAllowed
            else { return }
            secretText = text
            secretReveal.reveal(at: .now)
        }
    }

    func endSecretReveal() {
        secretHideCount += 1
        secretReveal.hide()
        secretText = nil
    }
}
