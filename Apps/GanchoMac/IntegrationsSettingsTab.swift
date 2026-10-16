import GanchoDesign
import SwiftUI

struct IntegrationsSettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Local MCP server") {
                Toggle(
                    "Allow approved local AI clients",
                    isOn: Binding(
                        get: { model.mcpConfig.isEnabled },
                        set: { model.setMCPEnabled($0) }))
                LabeledContent(
                    "Active client grants", value: "\(model.mcpConfig.activeGrants.count)")
                Text(
                    "Every client has its own board, time window, expiry, and read/write policy."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                Button("Open MCP Access…") { model.mcpAccessWindow.show(model: model) }
                    .accessibilityIdentifier("open-mcp-access")
                Text(
                    "Create, copy, expire, and revoke client grants from MCP Access."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(GanchoTokens.Spacing.md)
        .accessibilityIdentifier("settings-integrations")
    }
}
