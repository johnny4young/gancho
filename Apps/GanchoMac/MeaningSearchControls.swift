import GanchoAppCore
import GanchoDesign
import SwiftUI

struct MeaningSearchControls: View {
    @Bindable var search: PanelSearchModel
    var body: some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            Toggle("By meaning", isOn: $search.meaningEnabled)
                .toggleStyle(.button)
                .accessibilityIdentifier("meaning-search-toggle")
            if search.meaningEnabled {
                if search.meaning.status == .loading { ProgressView().controlSize(.mini) }
                Text(statusLabel)
                    .panelFont(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("meaning-search-status")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, GanchoTokens.Spacing.sm)
    }
    private var statusLabel: LocalizedStringKey {
        switch search.meaning.status {
        case .idle: "Enter a search; regex uses conventional results only."
        case .loading: "Finding related clips…"
        case .ready: "Related suggestions may include weak matches."
        case .incomplete: "Some clips are not indexed; conventional search remains complete."
        case .unavailable: "Meaning search unavailable; conventional search still works."
        case .queryTooLong: "Meaning search accepts up to 1,000 characters and 4 KiB."
        }
    }
}
