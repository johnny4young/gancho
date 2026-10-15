import GanchoDesign
import GanchoKit
import SwiftUI

struct ProSettingsTab: View {
    @Environment(AppModel.self) private var model
    @State private var clipCount: Int?
    #if GANCHO_DIRECT_DOWNLOAD
        /// Result of the last deactivation, so a Lemon Squeezy outage is
        /// reported rather than swallowed — the slot may still be held.
        @State private var deactivationNote: String?
        /// Localized where it is STORED, because the note renders verbatim: it
        /// can also carry an arbitrary system error string, and feeding that to
        /// LocalizedStringKey would both fail to localize and let stray format
        /// tokens in the error be interpreted as placeholders.
        private static let slotNotReleasedNote = String(
            localized:
                "Removed from this Mac, but the Lemon Squeezy slot couldn’t be released. Free it in your account."
        )
    #endif

    var body: some View {
        Form {
            LabeledContent(
                "Plan",
                value: model.tier == .pro
                    ? String(localized: "Pro") : String(localized: "Free"))
            if let clipCount {
                LabeledContent("Clips kept for you", value: clipCount.formatted())
            }
            Button("See what Pro adds") {
                model.paywallWindow.show(trigger: .settingsPro, model: model)
            }
            Text(
                "Pro unlocks unlimited history, pins, boards, and encrypted iCloud sync across your devices."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            #if GANCHO_DIRECT_DOWNLOAD
                // Lemon Squeezy counts one activation per Mac, so moving a
                // license needs an explicit way to release this one. Without
                // it a user replacing their Mac would silently run out of
                // activations with no way to reclaim them from the app.
                if model.tier == .pro {
                    Section("License") {
                        Button("Deactivate this Mac") {
                            Task { await deactivate() }
                        }
                        .accessibilityIdentifier("deactivate-license")
                        if let deactivationNote {
                            Text(verbatim: deactivationNote)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Text(
                            "Frees this activation so the license can move to another Mac. Your history stays here."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                Section("Software Updates") {
                    Button("Check for Updates…") { model.updater.checkForUpdates() }
                    Text(
                        "Direct downloads update themselves automatically; you can also check now."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            #endif
            #if DEBUG
                Section {
                    Button {
                        model.resetSyncAndRepull()
                    } label: {
                        Text(verbatim: "Reset & re-pull sync")
                    }
                    .accessibilityIdentifier("debug-reset-sync")
                } header: {
                    Text(verbatim: "Debug")
                }
            #endif
        }
        .formStyle(.grouped)
        .padding(GanchoTokens.Spacing.md)
        .task {
            // "Kept for you" = everything on disk: the visible clips PLUS the
            // archived ones free-tier enforcement hides but never deletes (the
            // upgrade carrot). Pro releases all archives, so there the archived
            // term is 0 and this equals the visible count.
            guard let store = model.fullStore, let visible = try? await store.count() else {
                return
            }
            let archived = (try? await store.archivedCount()) ?? 0
            clipCount = visible + archived
        }
    }

    #if GANCHO_DIRECT_DOWNLOAD
        /// Releases the Lemon Squeezy slot. The local license is dropped either
        /// way — the user asked to sign out here — so an outage is reported as
        /// a note, not as a failure that leaves them stuck.
        private func deactivate() async {
            switch await model.deactivateLicense() {
            case .networkUnavailable:
                deactivationNote = Self.slotNotReleasedNote
            case .storageUnavailable(let reason):
                // System error text: already localized by the OS, shown as-is.
                deactivationNote = reason
            default:
                deactivationNote = nil
            }
        }
    #endif

}
