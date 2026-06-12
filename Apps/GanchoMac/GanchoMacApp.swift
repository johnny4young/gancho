import ClipboardCore
import GanchoAI
import GanchoDesign
import GanchoKit
import SwiftUI

/// Menu-bar shell (pre-alpha). The real panel (E6.1, Liquid Glass NSPanel with
/// global hotkey) replaces this once spikes S0.1/S0.3 land; this shell exists
/// so the target builds, runs, and proves the capture wiring end to end.
@main
struct GanchoMacApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Gancho", systemImage: "paperclip") {
            ContentView()
                .environment(model)
        }
        .menuBarExtraStyle(.window)
    }
}

@Observable
@MainActor
final class AppModel {
    var captures: [ClipItem] = []

    private let monitor = MacPasteboardMonitor()
    private let classifier = RuleClassifier()
    private let store = InMemoryClipboardStore()

    init() {
        monitor.onCapture = { [weak self] capture in
            guard let self else { return }
            let kind = classifier.classify(capture.text)
            let item = ClipItem(
                kind: kind,
                preview: String(capture.text.prefix(120)),
                contentHash: ClipItem.hash(of: capture.text, kind: kind),
                sourceAppBundleID: capture.sourceAppBundleID
            )
            Task {
                await self.store.insert(item)
                self.captures = await self.store.items()
            }
        }
        monitor.start()
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            Text("Gancho — pre-alpha")
                .font(.headline)
                .padding(.bottom, GanchoTokens.Spacing.xxs)

            if model.captures.isEmpty {
                Text("Copy something — it will appear here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.captures.prefix(5)) { item in
                    HStack(spacing: GanchoTokens.Spacing.xs) {
                        Text(item.kind.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(item.preview)
                            .lineLimit(1)
                    }
                }
            }

            Divider()
            Button("Quit Gancho") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(GanchoTokens.Spacing.md)
        .frame(width: 320)
    }
}
