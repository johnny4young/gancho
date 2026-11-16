import GanchoDesign
import GanchoKit
import SwiftUI

/// Whether a clip has reached iCloud, for the peek's sync fact.
enum PeekSyncState: Equatable {
    case synced, waiting
}

/// Re-reads the sync fact when the selection or the engine's status changes.
struct PeekSyncStateKey: Equatable {
    let id: UUID
    let status: SyncStatus
}

/// The provenance caption: kind, source app, age, boards, sync state and
/// expiry on one line. A masked clip shows only its kind and expiry, like its row.
struct PeekProvenanceHeader: View {
    let item: ClipItem
    let boards: [Pinboard]
    let syncState: PeekSyncState?
    let masksProvenance: Bool
    /// Off when the peek's own countdown already shows the expiry.
    var showsExpiry = true

    private struct Fact: Identifiable {
        let id: String
        let text: Text
        var ink = AnyShapeStyle(GanchoTokens.Palette.ink3)
    }

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(facts.enumerated()), id: \.element.id) { index, fact in
                HStack(spacing: 6) {
                    if index > 0 { Text(verbatim: "·").accessibilityHidden(true) }
                    fact.text
                        .foregroundStyle(fact.ink)
                        .lineLimit(1)
                        .accessibilityIdentifier(fact.id)
                }
            }
        }
        .peekCaps()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("peek-provenance")
    }

    private var facts: [Fact] {
        var facts = [Fact(id: "peek-kind", text: Text(item.kind.cardName))]
        if !masksProvenance {
            if let bundleID = item.sourceAppBundleID {
                facts.append(
                    Fact(
                        id: "peek-source-app",
                        text: Text(verbatim: SourceApp.displayName(forBundleID: bundleID))))
            }
            let age =
                item.createdAt > .now
                ? Text(item.createdAt, format: .dateTime.day().month().year())
                : Text("\(Text(item.createdAt, style: .relative)) ago")
            facts.append(Fact(id: "peek-age", text: age))
            if !boards.isEmpty { facts.append(Fact(id: "peek-boards", text: Text("Board"))) }
            facts += boards.map {
                Fact(id: "peek-board-\($0.id.uuidString)", text: $0.displayTitle)
            }
            switch syncState {
            case .synced: facts.append(Fact(id: "peek-sync-state", text: Text("Synced")))
            case .waiting: facts.append(Fact(id: "peek-sync-state", text: Text("Waiting to sync")))
            case nil: break
            }
        }
        if showsExpiry, let expiresAt = item.expiresAt {
            facts.append(
                Fact(
                    id: "peek-expiry",
                    text: Text("Expires in \(Text(expiresAt, style: .relative))"),
                    ink: AnyShapeStyle(GanchoTokens.Palette.warningInk)))
        }
        return facts
    }
}

extension View {
    /// The peek's captions and part labels: small mono capitals, letter-spaced.
    func peekCaps(size: CGFloat = 10) -> some View {
        panelFont(size: size, .medium, design: .monospaced)
            .tracking(size * 0.09)
            .textCase(.uppercase)
            .foregroundStyle(GanchoTokens.Palette.ink3)
    }
}
