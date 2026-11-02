import GanchoDesign
import SwiftUI

/// Marks a board an active MCP grant exposes: the full chip in the board's
/// header, the icon alone in the sidebar.
struct AgentExposedBadge: View {
    var compact = false

    var body: some View {
        if compact {
            // Secondary, so it turns white on a selected sidebar row.
            Image(systemName: "terminal")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .help(Text("Exposed to agents"))
                .accessibilityLabel(Text("Exposed to agents"))
        } else {
            Label("Exposed to agents", systemImage: "terminal")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .ganchoTintedPill(GanchoTokens.Palette.agent, wash: 0.15)
                .fixedSize()
        }
    }
}
