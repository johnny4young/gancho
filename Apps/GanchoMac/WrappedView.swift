import AppKit
import GanchoDesign
import GanchoKit
import SwiftUI

/// "Clipboard Wrapped": a shareable stats card — counters and kinds only,
/// generated and rendered 100% locally. The share artifact is a PNG the
/// user explicitly saves; nothing is posted anywhere by Gancho.
struct WrappedView: View {
    let stats: WrappedStats

    var body: some View {
        VStack(spacing: GanchoTokens.Spacing.md) {
            Image(systemName: "paperclip")
                .font(.system(size: 36))
                .foregroundStyle(.tint)
            Text("My Clipboard, Wrapped")
                .font(.title.bold())
            Text("\(stats.totalCaptured)")
                .font(.system(size: 64, weight: .heavy, design: .rounded))
            Text("clips captured")
                .foregroundStyle(.secondary)

            HStack(spacing: GanchoTokens.Spacing.lg) {
                statColumn(value: "\(stats.pastedBack)", labelKey: "pasted back")
                statColumn(value: stats.topKind ?? "—", labelKey: "favorite type")
                statColumn(value: "\(stats.secretsProtected)", labelKey: "secrets protected")
            }
            Text(verbatim: "gancho.app")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(GanchoTokens.Spacing.xl)
        .frame(width: 420, height: 420)
        .background(.background)
        .accessibilityIdentifier("wrapped-card")
    }

    private func statColumn(value: String, labelKey: LocalizedStringKey) -> some View {
        VStack {
            Text(value).font(.title2.bold())
            Text(labelKey).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Counters only — the artifact cannot leak content by construction.
struct WrappedStats: Sendable, Equatable {
    var totalCaptured: Int
    var pastedBack: Int
    var topKind: String?
    var secretsProtected: Int

    @MainActor
    static func gather(model: AppModel) async -> WrappedStats {
        let total = (try? await model.store.count()) ?? 0
        let recents = (try? await model.store.items(offset: 0, limit: 200)) ?? []
        let topKind = Dictionary(grouping: recents, by: \.kind)
            .max { $0.value.count < $1.value.count }?.key.rawValue
        return WrappedStats(
            totalCaptured: total,
            pastedBack: UserDefaults.standard.object(forKey: "first-pasteback-at") != nil
                ? max(1, UserDefaults.standard.integer(forKey: "pasteback-count")) : 0,
            topKind: topKind,
            secretsProtected: model.privacyEvents.eventCount(
                since: Date(timeIntervalSinceNow: -365 * 86_400)))
    }
}

@MainActor
enum WrappedExporter {
    /// Renders the card to a PNG at 2x for sharing.
    static func savePNG(stats: WrappedStats) {
        let renderer = ImageRenderer(content: WrappedView(stats: stats))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "gancho-wrapped.png"
        guard panel.runModal() == .OK, let url = panel.url,
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, "public.png" as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
