import GanchoAppCore
import GanchoDesign
import SwiftUI

/// What the Meaning mode is doing; the field's mode control turns it on.
struct MeaningSearchControls: View {
    let search: PanelSearchModel
    var body: some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            if search.meaning.status == .loading { ProgressView().controlSize(.mini) }
            if let statusLabel {
                Text(statusLabel)
                    .panelFont(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("meaning-search-status")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, GanchoTokens.Spacing.sm)
    }
    private var statusLabel: LocalizedStringKey? {
        switch search.meaning.status {
        case .idle:
            // Navigation cancels a pending request; the query is already there.
            search.query.isEmpty ? "Type a search to find clips by meaning." : nil
        case .loading: "Finding related clips…"
        case .ready: "Related suggestions may include weak matches."
        case .incomplete: "Some clips are not indexed; conventional search remains complete."
        case .unavailable: "Meaning search unavailable; conventional search still works."
        case .queryTooLong: "Meaning search accepts up to 1,000 characters and 4 KiB."
        }
    }
}
