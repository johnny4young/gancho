import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// The dial's side; its ring sits 7.5 pt inside.
private let dialSide: CGFloat = 150

/// A secret's stage in the peek: its lifetime as a dial, then the stored mask
/// (or the revealed text), its actions and what never happens to it.
struct PeekSecretHero<Actions: View>: View {
    let item: ClipItem
    let countdown: Countdown?
    let revealedText: String?
    let reveal: SecretReveal
    @ViewBuilder let actions: Actions
    @Environment(\.panelTypeScale) private var typeScale
    @State private var isWide = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.lg, style: .continuous)
        let wideWidth = (dialSide + 20 + 2 * 20 + 180) * typeScale
        let layout =
            isWide
            ? AnyLayout(HStackLayout(alignment: .center, spacing: 20 * typeScale))
            : AnyLayout(VStackLayout(alignment: .center, spacing: GanchoTokens.Spacing.sm))
        layout {
            if let countdown { dial(countdown) }
            details.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20 * typeScale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(GanchoTokens.Palette.surface(.card), in: shape)
        .overlay(
            shape.strokeBorder(
                GanchoTokens.Palette.hairline, lineWidth: GanchoTokens.Stroke.hairline)
        )
        // Narrower than dial, gap, padding and a verb column, the dial stacks above the token.
        .onGeometryChange(for: Bool.self) {
            $0.size.width >= wideWidth
        } action: {
            isWide = $0
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("peek-secret-hero")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            token
            actions.padding(.top, GanchoTokens.Spacing.md * typeScale)
            // Sync, the semantic index and agent reads all skip sensitive clips.
            if item.isSensitive {
                Label(
                    "Never indexed, never synced, never read by agents.",
                    systemImage: "checkmark.shield"
                )
                .panelFont(.caption2)
                .foregroundStyle(GanchoTokens.Palette.ink3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14 * typeScale)
                .accessibilityIdentifier("peek-secret-note")
            }
        }
    }

    /// One element for VoiceOver: the clock it shows, in a sentence.
    private func dial(_ countdown: Countdown) -> some View {
        TimelineView(.periodic(from: countdown.deadline, by: 1)) { context in
            let clock = countdown.clock(at: context.date)
            TimeRing(countdown, lineWidth: 3) {
                VStack(spacing: 6 * typeScale) {
                    Text(verbatim: clock)
                        .panelFont(size: 30, .medium, design: .monospaced)
                        .tracking(-1.2 * typeScale)
                        .foregroundStyle(
                            countdown.isUrgent(at: context.date)
                                ? GanchoTokens.Palette.danger : GanchoTokens.Palette.ink)
                    Text("Self-destructs").peekCaps(size: 8.5)
                }
            }
            .background(MinuteTickMarks(lineWidth: 3))
            .frame(width: 135 * typeScale, height: 135 * typeScale)
            .padding((dialSide - 135) / 2 * typeScale)
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
                    .panelFont(size: 15, design: .monospaced)
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
