import AppKit
import GanchoDesign
import SwiftUI

/// Settings scene: a sidebar of sections and the selected section's form.
/// Every control binds straight into the model, so changes apply live — no
/// restart, no Apply button. The sidebar replaced a horizontal pill strip that
/// clipped its last tabs at the fixed width and left every section fighting a
/// 400 pt window.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    @State private var tab: SettingsTab = .general
    @State private var showMigrationImporter = false
    @State private var appliedMigrationUITestLaunch = false

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $tab)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text(tab.titleKey)
                    .font(.title2.weight(.bold))
                    .padding(.horizontal, GanchoTokens.Spacing.xl)
                    .padding(.top, GanchoTokens.Spacing.lg)
                selectedTab
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 760, height: 500)
        // A container, not a plain group: SwiftUI otherwise writes this
        // identifier onto every descendant (the sidebar buttons lost their
        // `settings-tab-<id>` to it).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings")
        .sheet(isPresented: $showMigrationImporter) {
            MigrationImportView()
        }
        .onAppear { showMigrationImporterForUITestIfRequested() }
    }

    @ViewBuilder private var selectedTab: some View {
        switch tab {
        case .general:
            GeneralSettingsTab { showMigrationImporter = true }
        case .capture: CaptureSettingsTab()
        case .retention: RetentionSettingsTab()
        case .privacy: PrivacySettingsTab()
        case .integrations: IntegrationsSettingsTab()
        case .pro: ProSettingsTab()
        case .about: AboutSettingsTab()
        }
    }

    private func showMigrationImporterForUITestIfRequested() {
        #if DEBUG
            guard !appliedMigrationUITestLaunch,
                model.storageIsEphemeral,
                CommandLine.arguments.contains("-show-migration-importer")
            else { return }
            appliedMigrationUITestLaunch = true
            showMigrationImporter = true
        #endif
    }
}

/// The Settings sections. Each one is a sidebar row with a symbol; the
/// selected row takes the accent (brand green unless the OS accent is set).
private enum SettingsTab: String, CaseIterable, Identifiable {
    case general, capture, retention, privacy, integrations, pro, about

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .capture: "Capture"
        case .retention: "Retention"
        case .privacy: "Privacy"
        case .integrations: "Integrations"
        case .pro: "Pro"
        case .about: "About"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .capture: "doc.on.clipboard"
        case .retention: "clock"
        case .privacy: "lock.shield"
        case .integrations: "puzzlepiece.extension"
        case .pro: "sparkles"
        case .about: "info.circle"
        }
    }
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsTab

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsTab.allCases) { tab in
                sidebarRow(tab)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, GanchoTokens.Spacing.sm)
        // The window's title bar is transparent and content-sized, so the
        // traffic lights sit over this column: keep the first row under them.
        .padding(.top, 38)
        .frame(width: 210)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// Plain buttons rather than a selectable `List`: the rows stay buttons to
    /// accessibility (the UI suites click `settings-tab-<id>`), and selection
    /// is one state the window owns.
    private func sidebarRow(_ tab: SettingsTab) -> some View {
        let isActive = tab == selection
        return Button {
            selection = tab
        } label: {
            Label {
                Text(tab.titleKey)
                    .font(.callout.weight(isActive ? .semibold : .regular))
            } icon: {
                Image(systemName: tab.symbolName)
                    .font(.callout)
                    .frame(width: 18)
            }
            .lineLimit(1)
            .padding(.horizontal, GanchoTokens.Spacing.sm)
            .padding(.vertical, GanchoTokens.Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .background(
                isActive ? GanchoTokens.Palette.accent : Color.clear,
                in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.sm, style: .continuous)
            )
            .contentShape(
                RoundedRectangle(cornerRadius: GanchoTokens.Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityIdentifier("settings-tab-\(tab.rawValue)")
    }
}
