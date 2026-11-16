import ClipboardCore
import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// The panel's operational footer: capture health, sync, the paste stack, and
/// the keys the dock does not already show. It owns presentation only; the
/// panel remains the navigation and action owner.
struct PanelStatusFooter: View {
    let syncStatus: SyncStatus
    let chip: PanelCaptureChip
    var privateModeStart: Date?
    /// The recorded Private Mode shortcut; with none there is no "off" hint.
    let privateModeShortcut: String?
    /// "↓ use fuzzy" while a query matches nothing and an alternative does.
    var alternativeHint: LocalizedStringKey?
    /// "I eyedropper" while the selected clip is a visible image.
    var offersEyedropper = false
    let showKeyboardShortcuts: () -> Void

    var body: some View {
        HStack(spacing: GanchoTokens.Spacing.md) {
            PanelCaptureChipView(chip: chip, privateModeStart: privateModeStart)
            SyncStatusView(status: syncStatus, isQuiet: true)
            PasteStackStrip()
            Spacer(minLength: 0)
            if let alternativeHint {
                keyboardHint(alternativeHint, keys: ["↓"])
            }
            if offersEyedropper {
                keyboardHint("eyedropper", keys: ["I"])
            }
            if case .privateMode = chip, let privateModeShortcut {
                keyboardHint("off", keys: PanelFirstRunStage.keycaps(for: privateModeShortcut))
            }
            // The dock shows the key of each of its verbs, so none repeats here.
            keyboardHint("navigate", keys: ["↑", "↓"])
            keyboardHint("paste nth", keys: ["⌘", "1–9"])
            Button(action: showKeyboardShortcuts) {
                keyboardHint("keys", keys: ["⌘/"]).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Keyboard shortcuts (⌘/)")
            .accessibilityLabel(Text("Keyboard shortcuts"))
            .accessibilityIdentifier("panel-shortcuts-button")
        }
        .panelFont(.caption2)
        .foregroundStyle(GanchoTokens.Palette.ink3)
        .padding(.top, GanchoTokens.Spacing.xxs)
        .padding(.horizontal, GanchoTokens.Spacing.xxs)
    }

    private func keyboardHint(_ label: LocalizedStringKey, keys: [String]) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in KeyCap(key) }
            }
            .accessibilityHidden(true)
            Text(label)
        }
    }
}

/// The footer's capture state: the live dot while capturing, Private Mode's
/// time left as a ring, otherwise a colour and its cause.
struct PanelCaptureChipView: View {
    let chip: PanelCaptureChip
    /// Private Mode's start: the ring empties from here to the deadline.
    var privateModeStart: Date?
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
        Group {
            if case .capturing(let app) = chip {
                HStack(spacing: 7) {
                    LiveDot(size: 7 * typeScale)
                    Text("Capturing").panelFont(.caption2, .medium).lineLimit(1)
                    if let app {
                        // The label still says the app is in front.
                        Text(verbatim: "· \(app)").panelFont(.caption2).lineLimit(1)
                            .foregroundStyle(GanchoTokens.Palette.ink3)
                    }
                }
                .frame(height: 20 * typeScale)
                .foregroundStyle(GanchoTokens.Palette.ink2)
            } else if case .privateMode(let end) = chip {
                HStack(spacing: 6) {
                    ModeRing(Countdown(from: privateModeStart, until: end))
                        .frame(width: 11 * typeScale, height: 11 * typeScale)
                    Text("Private").panelFont(.caption2, .medium).lineLimit(1)
                    if let end {
                        Text("· \(PanelCaptureChip.minutesLeft(until: end, now: now)) min left")
                            .panelFont(.caption2).lineLimit(1)
                            .foregroundStyle(GanchoTokens.Palette.ink3)
                    }
                }
                .frame(height: 20 * typeScale)
                .foregroundStyle(GanchoTokens.Palette.ink2)
            } else if case .paused = chip {
                // A pause is a state, not a warning: a hollow ink ring, no pill.
                HStack(spacing: 6) {
                    Circle().strokeBorder(GanchoTokens.Palette.ink3, lineWidth: 1.4)
                        .frame(width: 9 * typeScale, height: 9 * typeScale)
                    Text(title(now: now)).panelFont(.caption2, .medium).lineLimit(1)
                }
                .frame(height: 20 * typeScale)
                .foregroundStyle(GanchoTokens.Palette.ink2)
            } else {
                HStack(spacing: 5) {
                    Circle().fill(tint).frame(width: 7 * typeScale, height: 7 * typeScale)
                    Text(title(now: now)).panelFont(.caption2, .bold).lineLimit(1)
                }
                .padding(.horizontal, GanchoTokens.Spacing.xs)
                .frame(height: 20 * typeScale)
                .ganchoTintedPill(tint, wash: 0.16)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spokenTitle(now: now)))
        .accessibilityIdentifier("capture-indicator")
    }

    /// The spoken label, also shown for the paused and denied pills.
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
        case .privateMode: GanchoTokens.Palette.ink
        case .paused: GanchoTokens.Palette.ink3
        case .denied: GanchoTokens.Palette.danger
        }
    }
}

/// Renders the one policy-selected reason capture is interrupted.
struct PanelCaptureNoticeView: View {
    let notice: PanelCaptureNotice
    /// Private Mode's start, deadline and skipped count.
    let preferences: CapturePreferences
    let privateModeShortcut: String?
    /// The app sharing the screen, named in the share notice.
    var sharingApp: String?
    /// Whether the share notice still hides previews (no "Show anyway" yet).
    var previewsHidden = true
    let perform: (PanelCaptureAction) -> Void

    var body: some View {
        let tint = self.tint
        HStack(spacing: GanchoTokens.Spacing.xs) {
            if notice == .privateMode {
                ModeRing(
                    Countdown(
                        from: preferences.privateModeStartedAt,
                        until: preferences.privateModeEndsAt), lineWidth: 2
                )
                .frame(width: 22, height: 22)
                .accessibilityLabel(Text("Private Mode time left"))
                .accessibilityIdentifier("private-mode-ring")
            } else {
                Image(systemName: symbol).foregroundStyle(ReadableInk(base: tint))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 0) {
                titleText.panelFont(.caption, .semibold)
                detailText.panelFont(.caption2).foregroundStyle(.secondary)
                if notice == .privateMode, let privateModeSpan {
                    privateModeSpan.panelFont(.caption2, digits: true)
                        .foregroundStyle(GanchoTokens.Palette.ink3)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if notice == .privateMode {
                turnOffButton
            } else if notice == .screenShare, previewsHidden {
                Button("Show anyway") { perform(.showPreviewsWhileSharing) }
                    .ganchoTextButton()
                    .panelFont(.caption, .medium)
                    .accessibilityIdentifier("screen-share-show-anyway")
            } else if let action = notice.action {
                Button(actionTitle(action)) { perform(action) }
                    .ganchoTextButton()
                    .panelFont(.caption, .medium)
            }
        }
        .padding(.horizontal, GanchoTokens.Spacing.sm)
        .padding(.vertical, GanchoTokens.Spacing.xs)
        .background(
            // Private Mode is a neutral state; the others keep their warning wash.
            notice == .privateMode
                ? AnyShapeStyle(GanchoTokens.Palette.controlFill)
                : AnyShapeStyle(tint.opacity(0.12)),
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
        case .privateMode, .screenShare, .paused: GanchoTokens.Palette.ink
        case .denied, .storageEphemeral: GanchoTokens.Palette.danger
        }
    }

    private var titleText: Text {
        switch notice {
        case .storageEphemeral: Text("History isn't being saved")
        case .privateMode: Text("Private Mode is on")
        case .denied: Text("Clipboard access is off")
        case .screenShare:
            if previewsHidden {
                Text("Screen share detected · previews hidden, capture paused")
            } else {
                Text("Screen share detected · capture paused")
            }
        case .paused: Text("Capture is paused")
        }
    }

    private var detailText: Text {
        switch notice {
        case .storageEphemeral:
            Text("Gancho couldn't open its secure storage — clips vanish when you quit.")
        case .privateMode:
            Text("\(preferences.privateModeSkippedCopies) copies skipped, none read.")
        case .denied: Text("Gancho can't see what you copy.")
        case .screenShare: shareDetail
        case .paused: Text("Resume capture to save new copies.")
        }
    }

    private var shareDetail: Text {
        switch (sharingApp, previewsHidden) {
        case (let app?, true): Text("\(app) is sharing. Rows show kinds only.")
        case (let app?, false): Text("\(app) is sharing. Previews are visible.")
        case (nil, true): Text("Rows show kinds only until sharing ends.")
        case (nil, false): Text("Previews are visible until sharing ends.")
        }
    }

    /// "On since 2:02 PM · off at 3:02 PM"; no end while it stays on.
    private var privateModeSpan: Text? {
        guard let start = preferences.privateModeStartedAt else { return nil }
        guard let end = preferences.privateModeEndsAt else {
            return Text("On since \(Self.clock(start))")
        }
        return Text("On since \(Self.clock(start)) · off at \(Self.clock(end))")
    }

    /// Inverse ink: the banner's one filled control, and not the accent.
    private var turnOffButton: some View {
        Button {
            perform(.resumePrivateMode)
        } label: {
            HStack(spacing: GanchoTokens.Spacing.xxs) {
                Text("Turn off")
                if let privateModeShortcut {
                    Text(verbatim: privateModeShortcut).opacity(0.7)
                }
            }
            .panelFont(.caption2, .bold)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .ganchoInverseBadge()
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
        case .showPreviewsWhileSharing: "Show anyway"
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
