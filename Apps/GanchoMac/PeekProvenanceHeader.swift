import GanchoDesign
import GanchoKit
import SwiftUI

/// Whether a clip has reached iCloud, for the peek's sync chip.
enum PeekSyncState: Equatable {
    case synced, waiting
}

/// Re-reads the sync chip when the selection or the engine's status changes.
struct PeekSyncStateKey: Equatable {
    let id: UUID
    let status: SyncStatus
}

/// The provenance row beside the kind pill: source app, age, boards, expiry
/// and the clip's sync state. A masked clip shows only the pill and its
/// expiry, like its row.
struct PeekProvenanceHeader: View {
    let item: ClipItem
    let boards: [Pinboard]
    let syncState: PeekSyncState?
    let masksProvenance: Bool

    var body: some View {
        FlowLayout(spacing: 6) {
            TypeBadge(kind: item.kind, style: .pill)
            if !masksProvenance {
                if let bundleID = item.sourceAppBundleID { appChip(bundleID) }
                chip(identifier: "peek-age") {
                    Image(systemName: "clock")
                    Text("\(Text(item.createdAt, style: .relative)) ago")
                }
                ForEach(boards) { board in
                    chip(identifier: "peek-board-\(board.id.uuidString)") {
                        BoardIdentityMark(board: board, size: 9)
                        board.displayTitle
                    }
                    .help(board.displayTitle)
                }
            }
            if let expiresAt = item.expiresAt { expiryChip(expiresAt) }
            if !masksProvenance, let syncState { syncChip(syncState) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("peek-provenance")
    }

    private func appChip(_ bundleID: String) -> some View {
        chip(identifier: "peek-source-app") {
            if let icon = SourceApp.icon(forBundleID: bundleID) {
                Image(nsImage: icon).resizable().frame(width: 12, height: 12)
            } else {
                Image(systemName: "app.dashed")
            }
            Text(SourceApp.displayName(forBundleID: bundleID))
        }
    }

    private func expiryChip(_ expiresAt: Date) -> some View {
        chip(
            identifier: "peek-expiry", ink: GanchoTokens.Palette.warningInk,
            fill: GanchoTokens.Palette.warning.opacity(0.18)
        ) {
            Image(systemName: "hourglass")
            Text(expiresAt, style: .relative)
        }
        .accessibilityLabel(Text("Expires in \(Text(expiresAt, style: .relative))"))
    }

    @ViewBuilder private func syncChip(_ state: PeekSyncState) -> some View {
        switch state {
        case .synced:
            chip(
                identifier: "peek-sync-state", ink: GanchoTokens.Palette.brandText,
                fill: GanchoTokens.Palette.brandTint
            ) {
                Image(systemName: "checkmark.icloud")
                Text("Synced")
            }
        case .waiting:
            chip(identifier: "peek-sync-state") {
                Image(systemName: "icloud.and.arrow.up")
                Text("Waiting to sync")
            }
        }
    }

    private func chip(
        identifier: String,
        ink: some ShapeStyle = Color.primary.opacity(0.8),
        fill: some ShapeStyle = Color.primary.opacity(0.07),
        @ViewBuilder content: () -> some View
    ) -> some View {
        HStack(spacing: 4) { content() }
            .panelFont(.subheadline, .semibold)
            .lineLimit(1)
            .foregroundStyle(ink)
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background(fill, in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(identifier)
    }
}
