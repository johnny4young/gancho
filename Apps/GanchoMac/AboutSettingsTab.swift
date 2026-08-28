import GanchoDesign
import GanchoKit
import SwiftUI

// Extracted from SettingsView.swift on the DenylistSettingsSection precedent:
// the About tab is self-contained, and the settings file sits at the lint
// file-length ceiling.
/// The About screen: a centered app hero, a details card (version, author,
/// license), and the project links — with a manual update check on the
/// direct-download build. Scrolls so nothing is clipped in the short window.
struct AboutSettingsTab: View {
    @Environment(AppModel.self) private var model

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: GanchoTokens.Spacing.lg) {
                hero
                detailsCard
                links
                #if GANCHO_DIRECT_DOWNLOAD
                    Button("Check for Updates…") { model.updater.checkForUpdates() }
                        .buttonStyle(.bordered)
                #endif
            }
            .padding(GanchoTokens.Spacing.lg)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("settings-about")
    }

    private var hero: some View {
        VStack(spacing: GanchoTokens.Spacing.xs) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text(verbatim: "Gancho").font(.title2.bold())
            Text("Your clipboard, private by design.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            detailRow("Version", versionLine, id: "about-version")
            Divider()
            detailRow("Author", "Johnny IV Young Ospino")
            Divider()
            detailRow("License", "MIT")
        }
        .ganchoSurface(radius: GanchoTokens.Radius.md)
    }

    private func detailRow(
        _ label: LocalizedStringKey, _ value: String, id: String? = nil
    ) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: GanchoTokens.Spacing.md)
            let valueText = Text(value).textSelection(.enabled)
            // Only set an identifier when one is given — a blank id is a
            // meaningless, collision-prone query target for UI tests.
            if let id {
                valueText.accessibilityIdentifier(id)
            } else {
                valueText
            }
        }
        .font(.callout)
        .padding(.horizontal, GanchoTokens.Spacing.md)
        .padding(.vertical, GanchoTokens.Spacing.sm)
    }

    private var links: some View {
        VStack(spacing: GanchoTokens.Spacing.xxs) {
            aboutLink("Website", systemImage: "safari", url: "https://gancho.app")
            aboutLink(
                "Source code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right",
                url: "https://github.com/johnny4young/gancho")
            aboutLink(
                "Report an issue", systemImage: "exclamationmark.bubble",
                url: "https://github.com/johnny4young/gancho/issues")
        }
    }

    private func aboutLink(
        _ title: LocalizedStringKey, systemImage: String, url: String
    ) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: GanchoTokens.Spacing.sm) {
                Image(systemName: systemImage)
                    .foregroundStyle(GanchoTokens.Palette.accent)
                    .frame(width: 18)
                Text(title)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .font(.callout)
            .padding(.horizontal, GanchoTokens.Spacing.md)
            .padding(.vertical, GanchoTokens.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .ganchoSurface(radius: GanchoTokens.Radius.sm)
    }
}
