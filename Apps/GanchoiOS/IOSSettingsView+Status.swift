import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

extension IOSSettingsView {
    func statusRow(_ title: LocalizedStringKey, systemImage: String, subtitle: Text) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                subtitle.font(.footnote).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage).foregroundStyle(GanchoTokens.Palette.accentInk)
        }
    }

    /// Free shows what is used of each limit; Pro says the limits are gone.
    var proSubtitle: Text {
        guard model.tier != .pro else { return Text("Pro · every limit removed") }
        let meter = LibraryProMeter(
            boards: model.boards.filter { !$0.isSystem }.count, pins: 0, snippets: snippetCount)
        let boards = meter.ceilings.first { $0.kind == .boards }
        let snippets = meter.ceilings.first { $0.kind == .snippets }
        return Text(
            "Free · \(boards?.used ?? 0) of \(boards?.limit ?? 0) boards, \(snippets?.used ?? 0) of \(snippets?.limit ?? 0) snippets"
        )
    }

    var intelligenceSubtitle: Text {
        let summary = IntelligenceSummary(model.intelligence)
        let on = list(summary.on)
        let off = list(summary.off)
        // Named, not "All on": Intelligence has toggles this line doesn't cover.
        switch (summary.on.isEmpty, summary.off.isEmpty) {
        case (false, true): return Text("\(on) on")
        case (true, false): return Text("\(off) off")
        case (false, false): return Text("\(on) on · \(off) off")
        case (true, true): return Text(verbatim: "")
        }
    }

    private func list(_ features: [IntelligenceSummary.Feature]) -> String {
        features.map { feature in
            switch feature {
            case .titles: String(localized: "Titles")
            case .meaning: String(localized: "Meaning")
            case .screenshots: String(localized: "Screenshots")
            case .smartPaste: String(localized: "Smart paste")
            }
        }
        .formatted(.list(type: .and))
    }

    /// The constant zero of the Privacy Center hero, and what is masked now.
    var privacySubtitle: Text {
        Text("0 analytics requests · \(maskedCount) masked now")
    }

    /// Every way to capture on iPhone, as it is: iOS can't say whether the
    /// keyboard or the widget was added, so those rows open their steps.
    var capturePathsSection: some View {
        Section {
            captureRow(
                "Paste button", systemImage: "doc.on.clipboard",
                detail: "Saves what is on the clipboard — iOS asks nothing, shows no banner")
            captureRow(
                "Share sheet", systemImage: "square.and.arrow.up",
                detail: "Send text, links or images from any app"
            ) {
                Text("On").foregroundStyle(.secondary)
            }
            Link(destination: URL(string: "https://gancho.app/shortcuts")!) {
                captureRow(
                    "Shortcuts & Action Button", systemImage: "bolt",
                    detail: "Example Shortcuts gallery")
            }
            .tint(.primary)
            .accessibilityIdentifier("settings-shortcuts-gallery")
            Button {
                guide = .keyboard
            } label: {
                captureRow(
                    "Gancho keyboard", systemImage: "keyboard",
                    detail: "Settings › General › Keyboard › Keyboards")
            }
            .tint(.primary)
            .accessibilityIdentifier("settings-keyboard-how")
            Button {
                guide = .widget
            } label: {
                captureRow(
                    "Widget", systemImage: "square.grid.2x2",
                    detail: "Recent clips + Save, from the Home Screen")
            }
            .tint(.primary)
            .accessibilityIdentifier("settings-widget-how")
        } header: {
            Text("Capture on iPhone")
        } footer: {
            Text(
                "Gancho never reads your pasteboard in the background. Capture happens only when you act."
            )
        }
    }

    private func captureRow(
        _ title: LocalizedStringKey, systemImage: String, detail: LocalizedStringKey,
        @ViewBuilder trailing: () -> some View = { EmptyView() }
    ) -> some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: systemImage).foregroundStyle(GanchoTokens.Palette.accentInk)
            }
            Spacer(minLength: 0)
            trailing()
        }
    }
}
