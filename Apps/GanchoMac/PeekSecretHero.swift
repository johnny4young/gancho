import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// A secret's stage in the peek: its lifetime as a dial, then the stored mask
/// (or the revealed text), its actions and what never happens to it.
struct PeekSecretHero<Actions: View>: View {
    let item: ClipItem
    let countdown: Countdown?
    let revealedText: String?
    let reveal: SecretReveal
    @ViewBuilder let actions: Actions
    @Environment(\.panelTypeScale) private var typeScale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.lg, style: .continuous)
        HStack(alignment: .center, spacing: GanchoTokens.Spacing.md) {
            if let countdown { dial(countdown) }
            VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
                token
                actions
                // Sync, the semantic index and agent reads all skip sensitive clips.
                if item.isSensitive {
                    Label(
                        "Never indexed, never synced, never read by agents.",
                        systemImage: "checkmark.shield"
                    )
                    .panelFont(.caption2)
                    .foregroundStyle(GanchoTokens.Palette.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("peek-secret-note")
                }
            }
        }
        .padding(GanchoTokens.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GanchoTokens.Palette.surface(.card), in: shape)
        .overlay(
            shape.strokeBorder(
                GanchoTokens.Palette.hairline, lineWidth: GanchoTokens.Stroke.hairline)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("peek-secret-hero")
    }

    /// One element for VoiceOver: the clock it shows, in a sentence.
    private func dial(_ countdown: Countdown) -> some View {
        TimelineView(.periodic(from: countdown.deadline, by: 1)) { context in
            let clock = countdown.clock(at: context.date)
            TimeRing(countdown, lineWidth: 3) {
                VStack(spacing: 2) {
                    Text(verbatim: clock)
                        .panelFont(size: 25, .medium, design: .monospaced)
                        .foregroundStyle(
                            countdown.isUrgent(at: context.date)
                                ? GanchoTokens.Palette.danger : GanchoTokens.Palette.ink)
                    Text("Self-destructs")
                        .panelFont(size: 8.5, .medium, design: .monospaced)
                        .textCase(.uppercase)
                        .foregroundStyle(GanchoTokens.Palette.ink3)
                }
            }
            .frame(width: 108 * typeScale, height: 108 * typeScale)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Self-destructs in \(clock)"))
            .accessibilityIdentifier("peek-secret-countdown")
        }
    }

    private var token: some View {
        // The window is checked here too, so a late timer never extends it.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let shown = reveal.isRevealed(at: context.date) ? revealedText : nil
            HStack(alignment: .top, spacing: GanchoTokens.Spacing.xs) {
                Text(verbatim: shown ?? ClipSafePresentation.maskedTail(for: item))
                    .panelFont(.body, .medium, design: .monospaced)
                    .lineLimit(shown == nil ? 1 : 6)
                    .accessibilityIdentifier(shown == nil ? "peek-masked" : "peek-revealed")
                if shown != nil, let until = reveal.until {
                    TimeRing(
                        Countdown(window: SecretReveal.window, endingAt: until),
                        warnsWhenUrgent: false
                    )
                    .frame(width: 14 * typeScale, height: 14 * typeScale)
                    .accessibilityLabel(Text("Reveal time left"))
                    .accessibilityIdentifier("peek-reveal-ring")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
