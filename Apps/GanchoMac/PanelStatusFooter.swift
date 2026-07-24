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
    let capture: PanelCapturePresentation
    let showKeyboardShortcuts: () -> Void

    var body: some View {
        HStack(spacing: GanchoTokens.Spacing.md) {
            SyncStatusView(status: syncStatus)
            captureIndicator
            PasteStackStrip()
            Spacer(minLength: 0)
            keyboardHint("navigate", keys: ["arrow.up", "arrow.down"])
            keyboardHint("actions", keys: ["arrow.right"])
            keyboardHint("paste", keys: ["return"])
            Button(action: showKeyboardShortcuts) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Keyboard shortcuts (⌘/)")
            .accessibilityLabel("Keyboard shortcuts")
            .accessibilityIdentifier("panel-shortcuts-button")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.top, GanchoTokens.Spacing.xxs)
        .padding(.horizontal, GanchoTokens.Spacing.xxs)
    }

    private var captureIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(capture.isCapturing ? GanchoTokens.Palette.success : Color.secondary)
                .frame(width: 6, height: 6)
            Text(capture.isCapturing ? "Capturing" : "Paused")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            capture.isCapturing ? Text("Capturing") : Text("Capture paused")
        )
        .accessibilityIdentifier("capture-indicator")
    }

    private func keyboardHint(_ label: LocalizedStringKey, keys: [String]) -> some View {
        HStack(spacing: GanchoTokens.Spacing.xxs) {
            ForEach(keys, id: \.self) { key in
                Image(systemName: key)
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 17, height: 16)
                    .background(
                        .quaternary,
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            Text(label)
        }
    }
}

/// Renders the one policy-selected reason capture is interrupted.
struct PanelCaptureNoticeView: View {
    let notice: PanelCaptureNotice
    let perform: (PanelCaptureAction) -> Void

    var body: some View {
        let tint = self.tint
        HStack(spacing: GanchoTokens.Spacing.xs) {
            Image(systemName: symbol).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let action = notice.action {
                Button(actionTitle(action)) { perform(action) }
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.medium))
            }
        }
        .padding(.horizontal, GanchoTokens.Spacing.sm)
        .padding(.vertical, GanchoTokens.Spacing.xs)
        .background(
            tint.opacity(0.12),
            in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
        )
        .padding(.horizontal, GanchoTokens.Spacing.xxs)
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
        case .privateMode, .screenShare, .paused: GanchoTokens.Palette.warning
        case .denied, .storageEphemeral: GanchoTokens.Palette.danger
        }
    }

    private var title: LocalizedStringKey {
        switch notice {
        case .storageEphemeral: "History isn't being saved"
        case .privateMode: "Private Mode is on"
        case .denied: "Clipboard access is off"
        case .screenShare: "Paused while screen sharing"
        case .paused: "Capture is paused"
        }
    }

    private var detail: LocalizedStringKey {
        switch notice {
        case .storageEphemeral:
            "Gancho couldn't open its secure storage — clips vanish when you quit."
        case .privateMode: "New copies aren't being saved."
        case .denied: "Gancho can't see what you copy."
        case .screenShare: "Capture resumes when you stop sharing."
        case .paused: "Resume capture to save new copies."
        }
    }

    private func actionTitle(_ action: PanelCaptureAction) -> LocalizedStringKey {
        switch action {
        case .resumePrivateMode, .resumeCapture: "Resume"
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
