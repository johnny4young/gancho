import AppKit
import GanchoDesign
import GanchoKit
import SwiftUI

/// On-device intelligence (the design's "Intelligence" screen): the pipeline a
/// clip flows through at capture, and a toggle per enrichment stage. Every
/// toggle gates a REAL stage in the capture pipeline; the deterministic tier-0
/// classifier is always on. Zero network, every tier.
struct IntelligenceView: View {
    @Environment(AppModel.self) private var model

    private struct Stage: Identifiable {
        let symbol: String
        let tint: Color
        let title: LocalizedStringKey
        let sub: LocalizedStringKey
        var id: String { "\(symbol)" }
    }

    private var stages: [Stage] {
        [
            .init(
                symbol: "doc.on.clipboard", tint: GanchoTokens.Palette.kindTint(for: .text),
                title: "Capture", sub: "Clip enters"),
            .init(
                symbol: "wand.and.stars", tint: GanchoTokens.Palette.kindTint(for: .uuid),
                title: "Tier 0 · Rules", sub: "<5 ms · always on"),
            .init(
                symbol: "sparkles", tint: GanchoTokens.Palette.accent,
                title: "Tier 1 · Apple Intelligence", sub: "Titles · fallback-safe"),
            .init(
                symbol: "lock", tint: GanchoTokens.Palette.kindTint(for: .secret),
                title: "Sensitive check", sub: "Mask + expire"),
            .init(
                symbol: "magnifyingglass", tint: GanchoTokens.Palette.kindTint(for: .url),
                title: "Indexed", sub: "FTS + embeddings"),
        ]
    }

    private let secrets: [LocalizedStringKey] = [
        "AWS keys", "Stripe keys", "GitHub tokens", "Slack tokens", "PEM private keys",
        "Credit cards", "High-entropy passwords",
    ]

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.md) {
            HStack {
                Label("Intelligence", systemImage: "sparkles")
                    .font(.title2.bold())
                Spacer()
                Label("On-device", systemImage: "lock.shield")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GanchoTokens.Palette.success)
            }

            pipeline

            Form {
                Section {
                    featureRow(
                        "wand.and.stars", GanchoTokens.Palette.kindTint(for: .uuid),
                        "Smart classification",
                        "A deterministic classifier tags each clip in under 5 ms — JWT, JSON, color, card, URL… — with zero network. Drives previews, Smart Actions, and masking.",
                        alwaysOn: true)
                    toggleRow(
                        "sparkles", GanchoTokens.Palette.accent, "Smarter titles",
                        "Apple Intelligence writes a short, specific title on-device, falling back to heuristics on any failure — and never puts a secret in a title.",
                        isOn: $model.intelligence.intelligentTitles)
                    toggleRow(
                        "magnifyingglass", GanchoTokens.Palette.kindTint(for: .url),
                        "Semantic search",
                        "Find a clip by meaning, not just exact words. A 512-dim embedding indexes history on-device; the model assets stay local.",
                        isOn: $model.intelligence.semanticSearch)
                    toggleRow(
                        "photo", GanchoTokens.Palette.kindTint(for: .image),
                        "Searchable screenshots",
                        "On-device OCR reads text out of image clips and adds it to the full-text index, so a screenshot is findable by the words inside it.",
                        isOn: $model.intelligence.searchableScreenshots)
                    toggleRow(
                        "sparkles", GanchoTokens.Palette.accent, "Smart paste",
                        "Rewrite a clip before pasting — summarize, fix grammar, change tone, or pull key points. Apple Intelligence runs on-device; secrets are never sent to the model.",
                        isOn: $model.intelligence.smartPaste)
                    toggleRow(
                        "square.stack", GanchoTokens.Palette.kindTint(for: .fileReference),
                        "Suggest boards",
                        "When a clip looks like ones you've filed before, gancho suggests the board it probably belongs to — one tap to file it. On-device, never automatic.",
                        isOn: $model.intelligence.autoBoard)
                } header: {
                    Text("Intelligence features")
                }

                Section {
                    toggleRow(
                        "lock", GanchoTokens.Palette.kindTint(for: .secret),
                        "Detect & mask secrets",
                        "If you copy a key by accident, gancho masks the preview (●●●● + last 4) and auto-expires it after 10 minutes. Deterministic, on-device.",
                        isOn: $model.intelligence.detectSecrets)
                    if model.intelligence.detectSecrets {
                        secretChips
                    }
                } header: {
                    Text("Sensitive data")
                }

                Section {
                    Label {
                        Text(
                            "Every tier runs on this Mac. No clip text is ever sent to a server — gancho has none."
                        )
                        .font(.footnote)
                    } icon: {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(GanchoTokens.Palette.success)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding(GanchoTokens.Spacing.md)
        .frame(width: 520, height: 600)
        .accessibilityIdentifier("intelligence")
    }

    /// The capture pipeline — how a clip is understood, stage by stage.
    private var pipeline: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: GanchoTokens.Spacing.xs) {
                ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                    VStack(spacing: 5) {
                        Image(systemName: stage.symbol)
                            .font(.system(size: 17))
                            .foregroundStyle(stage.tint)
                            .frame(width: 38, height: 38)
                            .background(stage.tint.opacity(0.13), in: .rect(cornerRadius: 11))
                        Text(stage.title).font(.caption2.weight(.semibold)).multilineTextAlignment(
                            .center)
                        Text(stage.sub).font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                    .frame(width: 92)
                    if index < stages.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, GanchoTokens.Spacing.xxs)
        }
    }

    private func featureRow(
        _ symbol: String, _ tint: Color, _ title: LocalizedStringKey,
        _ description: LocalizedStringKey, alwaysOn: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: GanchoTokens.Spacing.xs) {
                Image(systemName: symbol).foregroundStyle(tint).frame(width: 20)
                Text(title).font(.callout.weight(.medium))
                Spacer(minLength: 0)
                if alwaysOn {
                    Text("Always on")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(GanchoTokens.Palette.success)
                        .padding(.horizontal, GanchoTokens.Spacing.xs)
                        .padding(.vertical, 2)
                        .background(GanchoTokens.Palette.success.opacity(0.12), in: Capsule())
                }
            }
            Text(description).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func toggleRow(
        _ symbol: String, _ tint: Color, _ title: LocalizedStringKey,
        _ description: LocalizedStringKey, isOn: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: isOn) {
                HStack(spacing: GanchoTokens.Spacing.xs) {
                    Image(systemName: symbol).foregroundStyle(tint).frame(width: 20)
                    Text(title).font(.callout.weight(.medium))
                }
            }
            Text(description).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var secretChips: some View {
        FlowLayout(spacing: GanchoTokens.Spacing.xxs) {
            ForEach(Array(secrets.enumerated()), id: \.offset) { _, secret in
                Text(secret)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(GanchoTokens.Palette.kindTint(for: .secret))
                    .padding(.horizontal, GanchoTokens.Spacing.xs)
                    .padding(.vertical, 3)
                    .background(
                        GanchoTokens.Palette.kindTint(for: .secret).opacity(0.1), in: Capsule())
            }
        }
    }
}

/// A minimal wrapping HStack (the secret chips wrap to as many rows as needed).
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Window host for the Intelligence screen (menu-bar agent, no WindowGroup).
@MainActor
final class IntelligenceWindowController {
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let hosting = NSHostingController(
                rootView: IntelligenceView().environment(model).ganchoTinted())
            let created = NSWindow(contentViewController: hosting)
            created.title = String(localized: "Intelligence")
            created.styleMask = [.titled, .closable]
            created.isReleasedWhenClosed = false
            created.center()
            window = created
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
