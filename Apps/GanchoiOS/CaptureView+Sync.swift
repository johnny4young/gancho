import GanchoDesign
import GanchoKit
import SwiftUI

extension CaptureView {
    /// iCloud sync indicator. The steady states (off, synced) show nothing —
    /// the "ready to paste" Live Activity carries sync status now, so the
    /// history doesn't spend a card on a green "Synced" that's almost always
    /// true. Only the transient and the actionable states surface here.
    @ViewBuilder
    var syncStatusSection: some View {
        switch model.syncStatus {
        case .idle, .upToDate:
            EmptyView()
        case .syncing:
            syncRow(Text("Syncing…"), "arrow.triangle.2.circlepath")
        case .pending(let count):
            syncRow(
                Text("\(Text("Waiting to sync")) · \(String(count))"), "arrow.up.circle")
        case .paused(let cause):
            syncRow(
                Text(causeText(cause)), "pause.circle", tint: GanchoTokens.Palette.warning,
                retry: true)
        case .failed(let cause):
            syncRow(
                Text(causeText(cause)), "exclamationmark.icloud",
                tint: GanchoTokens.Palette.danger, retry: true)
        }
    }

    private func syncRow(
        _ text: Text, _ symbol: String, tint: Color = .secondary, retry: Bool = false
    ) -> some View {
        Section {
            HStack {
                Label {
                    text
                } icon: {
                    // "Synced" reads green (a state); paused/failed warn — like macOS.
                    Image(systemName: symbol).foregroundStyle(ReadableInk(base: tint))
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                // A paused/failed sync was informational only; give it a way out.
                if retry {
                    Spacer(minLength: GanchoTokens.Spacing.sm)
                    Button("Retry") { model.syncNow() }
                        .font(.footnote)
                        .ganchoTextButton()
                        .accessibilityIdentifier("sync-retry")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("sync-status")
        }
    }

    private func causeText(_ cause: SyncInterruption) -> LocalizedStringKey {
        switch cause {
        case .iCloudFull: "iCloud storage is full"
        case .notSignedIn: "Not signed in to iCloud"
        case .offline: "No internet connection"
        case .unknown: "Sync error"
        }
    }
}
