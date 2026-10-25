import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// Settings › Privacy opens with four answers: is it capturing, is it
/// encrypted, what did it refuse this week, and does it sync.
struct PrivacyStatusTiles: View {
    @Environment(AppModel.self) private var model
    let overview: PrivacyOverview

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            captureTile
            encryptionTile
            tile(
                id: "privacy-status-skipped", symbol: "checkmark.shield",
                ink: .primary,
                value: Text("\(overview.protectedSkipsThisWeek) skipped this week"),
                detail: Text("protected copies · never stored"))
            syncTile
        }
    }

    private var chip: PanelCaptureChip {
        PanelCaptureChip.resolve(
            privateModeEnabled: model.preferences.isPrivateModePaused,
            privateModeEndsAt: model.preferences.privateModeEndsAt,
            runtimeStatus: model.monitorStatus.panelCaptureRuntimeStatus,
            frontApp: nil)
    }

    private var captureTile: some View {
        let size = overview.bytesOnDisk.formatted(.byteCount(style: .file))
        return tile(
            id: "privacy-status-capturing", dot: dotColor, ink: .primary,
            value: Text(verbatim: MenuBarMenu.stateTitle(chip)),
            detail: model.storageIsEphemeral
                ? Text("\(overview.clips) clips · not saved")
                : Text("\(overview.clips) clips · \(size) on this Mac"))
    }

    private var dotColor: Color {
        switch chip {
        case .capturing: GanchoTokens.Palette.success
        case .privateMode: GanchoTokens.Palette.indigo
        case .paused: GanchoTokens.Palette.warning
        case .denied: GanchoTokens.Palette.danger
        }
    }

    @ViewBuilder private var encryptionTile: some View {
        if model.storageIsEphemeral {
            tile(
                id: "privacy-status-encrypted", symbol: "externaldrive.badge.exclamationmark",
                ink: GanchoTokens.Palette.danger, value: Text("Not saved to disk"),
                detail: Text("A temporary store, cleared on quit"))
        } else if overview.encryption == nil {
            tile(
                id: "privacy-status-encrypted", symbol: "lock",
                ink: Color.secondary, value: Text("Checking encryption…"),
                detail: Text("SQLCipher · key in your Keychain"))
        } else if overview.encryption?.isVerified == false {
            tile(
                id: "privacy-status-encrypted", symbol: "lock.open",
                ink: GanchoTokens.Palette.danger, value: Text("Not encrypted"),
                detail: Text("Open the Privacy Center to verify"))
        } else {
            tile(
                id: "privacy-status-encrypted", symbol: "lock",
                ink: GanchoTokens.Palette.accentInk, value: Text("Encrypted at rest"),
                detail: Text("SQLCipher · key in your Keychain"))
        }
    }

    private var syncTile: some View {
        tile(
            id: "privacy-status-sync", symbol: "icloud", ink: syncInk, value: syncValue,
            detail: syncDetail)
    }

    private var syncValue: Text {
        switch model.syncStatus {
        case .idle: Text("Sync off")
        case .syncing: Text("Syncing")
        case .upToDate: Text("Synced")
        case .pending(let count): Text("\(count) waiting to sync")
        case .paused: Text("Sync paused")
        case .failed: Text("Sync failed")
        }
    }

    private var syncDetail: Text {
        switch model.syncStatus {
        case .idle: Text("iCloud private database · Pro")
        case .upToDate(let date?): Text("\(Text(date, style: .relative)) ago")
        case .paused(let cause), .failed(let cause): Text(SyncStatusView.causeText(cause))
        case .syncing, .upToDate, .pending: Text("iCloud private database")
        }
    }

    private var syncInk: AnyShapeStyle {
        switch model.syncStatus {
        case .idle: AnyShapeStyle(.secondary)
        case .syncing, .pending: AnyShapeStyle(.primary)
        case .upToDate: AnyShapeStyle(GanchoTokens.Palette.accentInk)
        case .paused: AnyShapeStyle(GanchoTokens.Palette.warningInk)
        case .failed: AnyShapeStyle(GanchoTokens.Palette.danger)
        }
    }

    private func tile(
        id: String, symbol: String? = nil, dot: Color? = nil, ink: some ShapeStyle, value: Text,
        detail: Text
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
                if let symbol { Image(systemName: symbol).font(.caption.weight(.semibold)) }
                value.font(.callout.weight(.bold)).lineLimit(2)
            }
            .foregroundStyle(ink)
            detail.font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: GanchoTokens.Radius.md)
                .strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
}
