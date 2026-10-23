import ClipboardCore
import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// The panel's operational footer: sync, capture health, paste stack, and the
/// compact keyboard legend. It owns presentation only; the panel remains the
/// navigation and action owner.
struct PanelStatusFooter: View {
    let syncStatus: SyncStatus
    let chip: PanelCaptureChip
    /// The recorded Private Mode shortcut; with none there is no "off" hint.
    let privateModeShortcut: String?
    /// "↓ use fuzzy" while a query matches nothing and an alternative does.
    var alternativeHint: LocalizedStringKey?
    /// "I eyedropper" while the selected clip is a visible image.
    var offersEyedropper = false
    let showKeyboardShortcuts: () -> Void
    @Environment(\.panelTypeScale) private var typeScale

    var body: some View {
        HStack(spacing: GanchoTokens.Spacing.md) {
            PanelCaptureChipView(chip: chip)
            SyncStatusView(status: syncStatus)
            PasteStackStrip()
            Spacer(minLength: 0)
            if let alternativeHint {
                keyboardHint(alternativeHint, keys: ["arrow.down"])
            }
            if offersEyedropper {
                keyboardHint("eyedropper", textKeys: ["I"])
            }
            if case .privateMode = chip, let privateModeShortcut {
                keyboardHint(
                    "off", textKeys: PanelFirstRunStage.keycaps(for: privateModeShortcut))
            }
            keyboardHint("navigate", keys: ["arrow.up", "arrow.down"])
            keyboardHint("actions", keys: ["arrow.right"])
            keyboardHint("paste", keys: ["return"])
            IconActionButton(
                "Keyboard shortcuts", systemImage: "questionmark.circle",
                identifier: "panel-shortcuts-button", help: "Keyboard shortcuts (⌘/)",
                action: showKeyboardShortcuts
            )
        }
        .panelFont(.caption2)
        .foregroundStyle(.secondary)
        .padding(.top, GanchoTokens.Spacing.xxs)
        .padding(.horizontal, GanchoTokens.Spacing.xxs)
    }

    private func keyboardHint(_ label: LocalizedStringKey, textKeys: [String]) -> some View {
        HStack(spacing: GanchoTokens.Spacing.xxs) {
            ForEach(Array(textKeys.enumerated()), id: \.offset) { _, key in
                Text(verbatim: key)
                    .panelFont(size: 9, .bold)
                    .frame(minWidth: 17 * typeScale, minHeight: 16 * typeScale)
                    .background(
                        .quaternary,
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            Text(label)
        }
    }

    private func keyboardHint(_ label: LocalizedStringKey, keys: [String]) -> some View {
        HStack(spacing: GanchoTokens.Spacing.xxs) {
            ForEach(keys, id: \.self) { key in
                Image(systemName: key)
                    .panelFont(size: 9, .semibold)
                    .frame(width: 17 * typeScale, height: 16 * typeScale)
                    .background(
                        .quaternary,
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            Text(label)
        }
    }
}

/// The footer's capture state: a colour, its cause and, while a Private Mode
/// countdown runs, the minutes left.
struct PanelCaptureChipView: View {
    let chip: PanelCaptureChip
    @Environment(\.panelTypeScale) private var typeScale

    var body: some View {
        if case .privateMode(.some) = chip {
            // Mounted only while a countdown runs.
            TimelineView(.periodic(from: .now, by: 15)) { context in
                pill(now: context.date)
            }
        } else {
            pill(now: .now)
        }
    }

    private func pill(now: Date) -> some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 7 * typeScale, height: 7 * typeScale)
            Text(title(now: now)).panelFont(.caption2, .bold).lineLimit(1)
        }
        .padding(.horizontal, GanchoTokens.Spacing.xs)
        .frame(height: 20 * typeScale)
        .ganchoTintedPill(tint, wash: wash)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spokenTitle(now: now)))
        .accessibilityIdentifier("capture-indicator")
    }

    private func title(now: Date) -> LocalizedStringKey {
        switch chip {
        case .capturing(let app?): "Capturing · \(app) in front"
        case .capturing: "Capturing"
        case .privateMode(let end?):
            "Private mode · \(PanelCaptureChip.minutesLeft(until: end, now: now)) min left"
        case .privateMode: "Private mode"
        case .paused(.screenShare): "Paused · screen sharing"
        case .paused(.screenLock): "Paused · screen locked"
        case .paused(.user): "Paused"
        case .denied: "Access denied"
        }
    }

    /// A bare "Paused" reads ambiguously out of context.
    private func spokenTitle(now: Date) -> LocalizedStringKey {
        chip == .paused(.user) ? "Capture paused" : title(now: now)
    }

    private var tint: Color {
        switch chip {
        case .capturing: GanchoTokens.Palette.success
        case .privateMode: GanchoTokens.Palette.indigo
        case .paused: GanchoTokens.Palette.warning
        case .denied: GanchoTokens.Palette.danger
        }
    }

    private var wash: Double {
        if case .privateMode = chip { 0.14 } else { 0.16 }
    }
}

/// Renders the one policy-selected reason capture is interrupted.
struct PanelCaptureNoticeView: View {
    let notice: PanelCaptureNotice
    /// Private Mode's start, deadline and skipped count.
    let preferences: CapturePreferences
    let privateModeShortcut: String?
    let perform: (PanelCaptureAction) -> Void

    var body: some View {
        let tint = self.tint
        HStack(spacing: GanchoTokens.Spacing.xs) {
            Image(systemName: symbol).foregroundStyle(ReadableInk(base: tint))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                titleText.panelFont(.caption, .semibold)
                    .foregroundStyle(
                        notice == .privateMode
                            ? AnyShapeStyle(ReadableInk(base: tint, onWash: 0.12))
                            : AnyShapeStyle(.primary))
                detailText.panelFont(.caption2).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if notice == .privateMode {
                turnOffButton
            } else if let action = notice.action {
                Button(actionTitle(action)) { perform(action) }
                    .ganchoTextButton()
                    .panelFont(.caption, .medium)
            }
        }
        .padding(.horizontal, GanchoTokens.Spacing.sm)
        .padding(.vertical, GanchoTokens.Spacing.xs)
        .background(
            tint.opacity(0.12),
            in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
        )
        .padding(.horizontal, GanchoTokens.Spacing.xxs)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture-notice")
    }

    private var symbol: String {
        switch notice {
        case .storageEphemeral: "externaldrive.badge.exclamationmark"
        case .privateMode: "eye.slash"
        case .denied: "exclamationmark.triangle.fill"
        case .screenShare: "rectangle.on.rectangle"
        case .paused: "pause.circle"
        }
    }

    private var tint: Color {
        switch notice {
        case .privateMode: GanchoTokens.Palette.indigo
        case .screenShare, .paused: GanchoTokens.Palette.warning
        case .denied, .storageEphemeral: GanchoTokens.Palette.danger
        }
    }

    private var titleText: Text {
        switch notice {
        case .storageEphemeral: Text("History isn't being saved")
        case .privateMode:
            if let start = preferences.privateModeStartedAt {
                Text("Private Mode is on · since \(Self.clock(start))")
            } else {
                Text("Private Mode is on")
            }
        case .denied: Text("Clipboard access is off")
        case .screenShare: Text("Paused while screen sharing")
        case .paused: Text("Capture is paused")
        }
    }

    private var detailText: Text {
        switch notice {
        case .storageEphemeral:
            Text("Gancho couldn't open its secure storage — clips vanish when you quit.")
        case .privateMode:
            Text(
                verbatim: String(
                    localized: "\(preferences.privateModeSkippedCopies) copies skipped, none read")
                    + " · " + privateModeEnd)
        case .denied: Text("Gancho can't see what you copy.")
        case .screenShare: Text("Capture resumes when you stop sharing.")
        case .paused: Text("Resume capture to save new copies.")
        }
    }

    private var privateModeEnd: String {
        if let end = preferences.privateModeEndsAt {
            String(localized: "turns off at \(Self.clock(end)) or when you say so")
        } else {
            String(localized: "stays on until you turn it off")
        }
    }

    /// Filled indigo, the one saturated control in the banner.
    private var turnOffButton: some View {
        Button {
            perform(.resumePrivateMode)
        } label: {
            HStack(spacing: GanchoTokens.Spacing.xxs) {
                Text("Turn off")
                if let privateModeShortcut {
                    Text(verbatim: privateModeShortcut).opacity(0.85)
                }
            }
            .panelFont(.caption2, .bold)
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(GanchoTokens.Palette.indigo, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("private-mode-turn-off")
    }

    private static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func actionTitle(_ action: PanelCaptureAction) -> LocalizedStringKey {
        switch action {
        case .resumePrivateMode: "Turn off"
        case .resumeCapture: "Resume"
        case .openPermissionSettings: "Fix"
        }
    }
}

extension MonitorStatus {
    var panelCaptureRuntimeStatus: PanelCaptureRuntimeStatus {
        switch self {
        case .stopped: .stopped
        case .running: .running
        case .pausedByUser: .pausedByUser
        case .pausedByScreenLock: .pausedByScreenLock
        case .pausedByScreenShare: .pausedByScreenShare
        case .deniedByPrivacySettings: .deniedByPrivacySettings
        }
    }
}
