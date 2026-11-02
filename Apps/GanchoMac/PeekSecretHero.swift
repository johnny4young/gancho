import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// A secret's card in the peek: the stored mask (or the revealed text), the
/// time it has left and a lifetime bar. Reveal and Delete now are peek actions.
struct PeekSecretHero: View {
    let item: ClipItem
    let lifetime: SecretLifetime?
    let revealedText: String?
    let reveal: SecretReveal

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.lg, style: .continuous)
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            // The window is checked here too, so a late timer never extends it.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let shown = reveal.isRevealed(at: context.date) ? revealedText : nil
                Text(verbatim: shown ?? ClipSafePresentation.maskedTail(for: item))
                    .panelFont(.body, design: .monospaced)
                    .fontWeight(.bold)
                    .lineLimit(shown == nil ? 1 : 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(shown == nil ? "peek-masked" : "peek-revealed")
            }
            if let lifetime {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    countdown(lifetime, at: context.date)
                }
            }
        }
        .padding(.vertical, GanchoTokens.Spacing.sm)
        .padding(.horizontal, GanchoTokens.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GanchoTokens.Palette.danger.opacity(0.06), in: shape)
        .overlay(
            shape.strokeBorder(
                GanchoTokens.Palette.danger.opacity(0.25), lineWidth: GanchoTokens.Stroke.hairline)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("peek-secret-hero")
    }

    private func countdown(_ lifetime: SecretLifetime, at now: Date) -> some View {
        let fraction = lifetime.fraction(at: now)
        // The row's badge uses the same system timer, so both tick together.
        let time =
            lifetime.remaining(at: now) > 0
            ? Text(lifetime.deadline, style: .timer) : Text(verbatim: "0:00")
        return VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            HStack(spacing: GanchoTokens.Spacing.xxs) {
                Image(systemName: "timer")
                Text("Self-destructs in \(time.monospacedDigit().bold())")
            }
            .panelFont(.caption)
            .foregroundStyle(GanchoTokens.Palette.warningInk)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("peek-secret-countdown")
            GeometryReader { proxy in
                Capsule()
                    .fill(GanchoTokens.Palette.warning.opacity(0.2))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(GanchoTokens.Palette.warning)
                            .frame(width: proxy.size.width * fraction)
                    }
            }
            .frame(height: 6)
            .accessibilityElement()
            .accessibilityLabel(Text("Lifetime left"))
            .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
            .accessibilityIdentifier("peek-secret-lifetime")
        }
    }
}
