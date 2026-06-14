import GanchoDesign
import GanchoKit
import SwiftUI

/// Glanceable iCloud sync indicator: a symbol plus the current state, with a
/// readable cause and a suggested action when paused or failed. Renders
/// nothing when sync is off (free tier / signed out). Shared by the floating
/// panel footer and the Privacy Center.
struct SyncStatusView: View {
    let status: SyncStatus
    /// The Privacy Center passes `true` to also show the suggested-action line.
    var showsSuggestion = false

    var body: some View {
        if case .idle = status {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xxs) {
                Label {
                    headlineText
                } icon: {
                    Image(systemName: symbol).foregroundStyle(tint)
                }
                .font(.footnote)
                if showsSuggestion, let suggestion {
                    Text(suggestion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, GanchoTokens.Spacing.lg)
                }
            }
            .accessibilityIdentifier("sync-status")
        }
    }

    private var headlineText: Text {
        switch status {
        case .idle: Text(verbatim: "")
        case .syncing: Text("Syncing…")
        case .upToDate: Text("Synced")
        case .pending(let count): Text("Waiting to sync") + Text(verbatim: " · \(count)")
        case .paused(let cause), .failed(let cause): Text(Self.causeText(cause))
        }
    }

    private var symbol: String {
        switch status {
        case .idle: ""
        case .syncing: "arrow.triangle.2.circlepath"
        case .upToDate: "checkmark.icloud"
        case .pending: "arrow.up.circle"
        case .paused: "pause.circle"
        case .failed: "exclamationmark.icloud"
        }
    }

    private var tint: Color {
        switch status {
        case .paused: .orange
        case .failed: .red
        default: .secondary
        }
    }

    private var suggestion: LocalizedStringKey? {
        switch status {
        case .paused(let cause), .failed(let cause): Self.suggestionText(cause)
        default: nil
        }
    }

    /// Readable cause — shared with the Privacy Center sync log.
    static func causeText(_ cause: SyncInterruption) -> LocalizedStringKey {
        switch cause {
        case .iCloudFull: "iCloud storage is full"
        case .notSignedIn: "Not signed in to iCloud"
        case .offline: "No internet connection"
        case .unknown: "Sync error"
        }
    }

    static func suggestionText(_ cause: SyncInterruption) -> LocalizedStringKey {
        switch cause {
        case .iCloudFull: "Free up space in iCloud settings."
        case .notSignedIn: "Sign in to iCloud in System Settings."
        case .offline: "Reconnect and Gancho will retry."
        case .unknown: "Gancho will retry automatically."
        }
    }
}
