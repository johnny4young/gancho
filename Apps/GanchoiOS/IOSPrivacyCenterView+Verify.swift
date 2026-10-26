import GanchoDesign
import GanchoKit
import SwiftUI

extension IOSPrivacyCenterView {
    /// The proofs first: encryption with a Verify that runs on this iPhone,
    /// sync, and what is masked right now.
    var verifySection: some View {
        Section("Verify, don’t trust") {
            LabeledContent {
                Button("Verify") {
                    verifying = true
                    Task {
                        verification = await model.verifyEncryption()
                        verifying = false
                    }
                }
                .disabled(verifying || model.storageIsEphemeral)
                .accessibilityIdentifier("ios-privacy-verify-encryption")
            } label: {
                Label {
                    // The claim follows the store: a fallback to memory is not encryption.
                    if model.storageIsEphemeral {
                        Text("Not saved to disk")
                        Text("A temporary store, cleared on quit")
                    } else {
                        Text("Encrypted at rest")
                        Text("SQLCipher · key in your Keychain")
                    }
                    if let verification { verificationResult(verification) }
                } icon: {
                    Image(systemName: model.storageIsEphemeral ? "externaldrive" : "lock")
                        .foregroundStyle(GanchoTokens.Palette.accentInk)
                }
            }
            Label {
                Text("iCloud sync")
                syncDetail
            } icon: {
                Image(systemName: "icloud").foregroundStyle(GanchoTokens.Palette.accentInk)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("ios-privacy-sync")
            LabeledContent {
                Text("\(masked)").monospacedDigit()
            } label: {
                Label {
                    Text("Secrets masked now")
                } icon: {
                    Image(systemName: "eye.slash").foregroundStyle(GanchoTokens.Palette.accentInk)
                }
            }
            .accessibilityIdentifier("ios-privacy-masked")
        }
    }

    /// Off on Free (sync is Pro); otherwise its state, with no device list,
    /// since none is stored.
    @ViewBuilder private var syncDetail: some View {
        if !model.syncController.isEnabled {
            Text("Off · Pro")
        } else {
            switch model.syncStatus {
            case .idle: Text("Private database")
            case .syncing: Text("Syncing…")
            case .pending(let count): Text("\(count) waiting to sync")
            case .upToDate(let date?):
                Text("Private database · \(Text(date, style: .relative)) ago")
            case .upToDate: Text("Private database · synced")
            case .paused: Text("Sync paused")
            case .failed: Text("Sync failed")
            }
        }
    }

    /// What Verify found: a pass names the cipher, a miss names what failed.
    private func verificationResult(_ report: StoreEncryptionReport) -> some View {
        Group {
            if report.isVerified, let version = report.cipherVersion {
                Text("Verified · SQLCipher \(version) · unreadable without its key")
                    .foregroundStyle(GanchoTokens.Palette.accentInk)
            } else if !report.fileFound {
                Text("There’s no database file on this iPhone to check.")
                    .foregroundStyle(GanchoTokens.Palette.danger)
            } else if !report.opensWithKey {
                Text("Couldn’t open the database with its key.")
                    .foregroundStyle(GanchoTokens.Palette.danger)
            } else {
                Text("The database file isn’t encrypted.")
                    .foregroundStyle(GanchoTokens.Palette.danger)
            }
        }
        .accessibilityIdentifier("ios-privacy-verify-result")
    }
}
