import GanchoDesign
import GanchoKit
import SwiftUI

extension PrivacyCenterView {
    /// The proofs first: encryption with a Verify that runs on this Mac, sync,
    /// the last content read, agent access and the network boundary.
    var verifySection: some View {
        Section("Verify, don’t trust") {
            verifyRow(symbol: "lock", tint: GanchoTokens.Palette.accentInk) {
                Text("History is encrypted on this Mac")
                Text(
                    "SQLCipher database, sealed image and file blobs. The key lives in your login Keychain."
                )
                if let verification { verificationResult(verification) }
            } action: {
                Button("Verify") {
                    verifying = true
                    Task {
                        verification = await model.verifyEncryption()
                        verifying = false
                    }
                }
                .disabled(verifying || model.storageIsEphemeral || model.fullStore == nil)
                .accessibilityIdentifier("privacy-verify-encryption")
            }
            verifyRow(symbol: "checkmark.icloud", tint: GanchoTokens.Palette.accentInk) {
                Text("iCloud sync")
                if case .idle = model.syncStatus {
                    Text("Off · your private iCloud database, with Pro")
                } else {
                    SyncStatusView(status: model.syncStatus, showsSuggestion: true)
                }
            } action: {
                Button("Force sync") { model.forceSync() }
                    .accessibilityIdentifier("force-sync")
            }
            verifyRow(symbol: "eye", tint: Color.secondary) {
                Text("Last content read")
                if let date = model.monitor.lastContentReadAt {
                    Text("\(Text(date, style: .relative)) ago")
                } else {
                    Text("Never")
                }
            } action: {
                EmptyView()
            }
            verifyRow(symbol: "puzzlepiece", tint: Color.secondary) {
                Text("Local AI agents (MCP)")
                Text(
                    model.mcpConfig.isEnabled
                        ? "On · \(mcpCalls) calls this week · \(mcpDenied) denied"
                        : "Off · \(mcpCalls) calls this week · \(mcpDenied) denied")
            } action: {
                Button("MCP Access…") { model.mcpAccessWindow.show(model: model) }
                    .accessibilityIdentifier("open-mcp-access")
            }
            verifyRow(symbol: "network", tint: Color.secondary) {
                Text("Network")
                Text(
                    // swiftlint:disable:next line_length
                    "Gancho never sends clipboard content to analytics. Optional iCloud sync uses your private iCloud account; verify the boundary with Little Snitch or any network monitor."
                )
            } action: {
                EmptyView()
            }
        }
    }

    private func verifyRow<Details: View, Action: View>(
        symbol: String, tint: some ShapeStyle, @ViewBuilder details: () -> Details,
        @ViewBuilder action: () -> Action
    ) -> some View {
        LabeledContent {
            action()
        } label: {
            Label {
                details()
            } icon: {
                Image(systemName: symbol).foregroundStyle(tint)
            }
        }
    }

    /// What Verify found, in the row: a pass names the cipher, a miss names what failed.
    private func verificationResult(_ report: StoreEncryptionReport) -> some View {
        Group {
            if report.isVerified, let version = report.cipherVersion {
                Text("Verified · SQLCipher \(version) · unreadable without its key")
                    .foregroundStyle(GanchoTokens.Palette.accentInk)
            } else if !report.fileFound {
                Text("There’s no database file on this Mac to check.")
                    .foregroundStyle(GanchoTokens.Palette.danger)
            } else if !report.opensWithKey {
                Text("Couldn’t open the database with its key.")
                    .foregroundStyle(GanchoTokens.Palette.danger)
            } else {
                Text("The database file isn’t encrypted.")
                    .foregroundStyle(GanchoTokens.Palette.danger)
            }
        }
        .accessibilityIdentifier("privacy-verify-result")
    }
}
