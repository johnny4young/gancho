import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

extension OnboardingView {
    /// Step 1: where clips live, how long secrets last, what is never read.
    var promiseStep: some View {
        let lifetime = OnboardingCopy.secretLifetime(model.retentionPolicy.sensitiveLifetime)
        return VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            OnboardingStepHeader(
                title: "Your clipboard, private by design",
                message: Text(
                    // swiftlint:disable:next line_length
                    "Gancho keeps everything you copy — text, links, code, colors, images — so you can find it and paste it again."
                )
            ) {
                Image("GanchoMark").resizable().frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 6) {
                promise(
                    "laptopcomputer",
                    Text(
                        "**Stays on this Mac.** Encrypted on disk. Nothing leaves unless you turn on iCloud sync."
                    ))
                promise(
                    "lock",
                    Text(
                        "**Secrets are masked and expire.** Keys, cards and passwords self-destruct after \(lifetime)."
                    ))
                promise(
                    "shield.lefthalf.filled",
                    Text(
                        "**Password managers are never read.** Copies they mark as concealed are sensed, not stored."
                    ))
            }
            .padding(.top, GanchoTokens.Spacing.xxs)
            Button("Open Privacy Center") { model.privacyCenterWindow.show(model: model) }
                .ganchoTextButton()
                .font(.system(size: 12, weight: .bold))
                .accessibilityIdentifier("onboarding-open-privacy-center")
        }
    }

    private func promise(_ symbol: String, _ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: GanchoTokens.Spacing.xs) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(GanchoTokens.Palette.accentInk)
                .frame(width: 14)
                .accessibilityHidden(true)
            text.font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// Step 2: Accessibility as a with/without choice, with the live status.
    var permissionStep: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            OnboardingStepHeader(
                title: "One permission for instant pasting",
                message: Text(
                    // swiftlint:disable:next line_length
                    "Gancho presses ⌘V for you in the app you came from. That needs Accessibility — the only permission it asks for, and never used to read your screen."
                )
            ) {
                Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "hand.raised")
                    .font(.system(size: 30))
                    .foregroundStyle(
                        accessibilityGranted
                            ? AnyShapeStyle(GanchoTokens.Palette.accentInk)
                            : AnyShapeStyle(GanchoTokens.Palette.warningInk))
            }
            HStack(alignment: .top, spacing: GanchoTokens.Spacing.xs) {
                comparison(
                    title: "With it",
                    detail:
                        // swiftlint:disable:next line_length
                        "Pick a clip, press ⏎, it lands where your cursor was. Paste stack and snippets work in one key."
                )
                comparison(
                    title: "Without it",
                    detail:
                        "Gancho copies the clip and you press ⌘V yourself. Everything else works the same."
                )
            }
            permissionStatus
        }
        // Polled only here: the other steps never read it.
        .onAppear { accessibilityGranted = Self.isAccessibilityTrusted() }
        .onReceive(accessibilityCheck) { _ in
            accessibilityGranted = Self.isAccessibilityTrusted()
        }
    }

    private func comparison(title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).fontWeight(.bold)
            Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11.5))
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: GanchoTokens.Radius.md)
                .strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline)
        )
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var permissionStatus: some View {
        Group {
            if accessibilityGranted {
                Label("Granted · Gancho can paste for you", systemImage: "checkmark")
                    .foregroundStyle(GanchoTokens.Palette.accentInk)
            } else {
                Label(
                    "Not granted yet · turns green when you come back",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(GanchoTokens.Palette.warningInk)
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .accessibilityIdentifier("onboarding-accessibility-status")
    }

    /// Step 4: copy something now and watch it land, then open the real panel.
    var firstCopyStep: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            OnboardingStepHeader(
                title: "Try it now",
                message: panelShortcut == nil
                    ? Text(
                        // swiftlint:disable:next line_length
                        "Copy any text in any app — it appears below instantly. Then click the hook in the menu bar to open the real panel and paste it back."
                    )
                    : Text(
                        // swiftlint:disable:next line_length
                        "Copy any text in any app — it appears below instantly. Then press your panel shortcut to open the real panel and paste it back."
                    )
            ) {
                Image(systemName: "clipboard")
                    .font(.system(size: 30))
                    .foregroundStyle(GanchoTokens.Palette.accentInk)
            }
            liveList
            firstCopyStatus
            Button("Import from Maccy or CSV…") { showMigrationImporter = true }
                .ganchoTextButton()
                .font(.system(size: 11.5, weight: .bold))
                .accessibilityIdentifier("onboarding-open-migration-importer")
        }
    }

    private var liveList: some View {
        VStack(spacing: 2) {
            if let latest = model.recentItems.first {
                ClipCard(item: latest, previewsHidden: model.previewsHidden)
            }
            Text("Your next copy lands here")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(GanchoTokens.Spacing.sm)
        }
        .padding(GanchoTokens.Spacing.xxs)
        .background(.background, in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.sm * 2))
        .overlay(
            RoundedRectangle(cornerRadius: GanchoTokens.Radius.sm * 2)
                .strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding-live-list")
    }

    @ViewBuilder private var firstCopyStatus: some View {
        let chip = model.captureChip(frontApp: nil)
        let isCapturing = if case .capturing = chip { true } else { false }
        Group {
            if !isCapturing {
                Label(MenuBarMenu.stateTitle(chip), systemImage: "pause.circle")
                    .foregroundStyle(GanchoTokens.Palette.warningInk)
            } else {
                // No title claim: nothing records whether auto-titling or the user wrote it.
                Label("Capturing", systemImage: "checkmark")
                    .foregroundStyle(GanchoTokens.Palette.accentInk)
            }
        }
        .font(.system(size: 11.5, weight: .semibold))
        .lineLimit(1)
        .accessibilityIdentifier("onboarding-capture-status")
    }
}
