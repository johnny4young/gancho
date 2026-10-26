import GanchoDesign
import GanchoKit
import SwiftUI

/// Welcome page 2: the "Sensed, not read" row before the user meets it, why
/// there is no paste banner, the optional extensions, and a real Paste button.
struct IOSOnboardingSensedPage: View {
    let onBack: () -> Void
    let onDone: () -> Void
    let onSaved: (ClipItem) -> Void
    @Environment(IOSAppModel.self) private var model
    @State private var guide: IOSOnboardingGuide?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 44))
                        .foregroundStyle(GanchoTokens.Palette.accentInk)
                        .accessibilityHidden(true)
                    Text("Sensed, not read")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(
                        // swiftlint:disable:next line_length
                        "This is the row you will see at the top of your history. Gancho only sees the **type** of what is on the clipboard — never the content — until you tap Paste."
                    )
                    .foregroundStyle(.secondary)
                }
                exampleRow
                Text(
                    // swiftlint:disable:next line_length
                    "iOS shows no “pasted from” banner because the Paste button is the system’s own control: your tap is the permission."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                options
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom) { pasteBar }
        .navigationTitle(Text("2 of 2"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back", action: onBack)
                    .accessibilityIdentifier("onboarding-back")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Get started", action: onDone)
                    .accessibilityIdentifier("onboarding-done")
            }
        }
        .sheet(item: $guide) { guide in
            IOSOnboardingGuideSheet(guide: guide)
        }
    }

    private var exampleRow: some View {
        HStack(spacing: GanchoTokens.Spacing.sm) {
            ClipTile(
                item: ClipItem(kind: .url, preview: "", contentHash: ""), size: 36,
                previewsHidden: true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Link on your clipboard").font(.subheadline.weight(.semibold))
                Label("Sensed, not read", systemImage: "shield.lefthalf.filled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.down")
                .font(.body.weight(.semibold))
                .foregroundStyle(GanchoTokens.Palette.accentInk)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, GanchoTokens.Spacing.sm)
        .background(
            GanchoTokens.Palette.accentTint,
            in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.lg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: GanchoTokens.Radius.lg)
                .strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding-sensed-example")
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            Text("Optional, set up later in Settings").font(.headline)
            option("keyboard", "Gancho keyboard", "Insert any clip while typing") {
                guideButton(.keyboard)
            }
            option("square.grid.2x2", "Home Screen widget", "Recent clips + Save") {
                guideButton(.widget)
            }
            option(
                "square.and.arrow.up", "Share sheet", "Already on — send anything to Gancho"
            ) {
                Text("On")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, GanchoTokens.Spacing.sm)
                    .frame(minHeight: 30)
                    .accessibilityIdentifier("onboarding-share-status")
            }
        }
    }

    private func guideButton(_ guide: IOSOnboardingGuide) -> some View {
        Button("How") { self.guide = guide }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .ganchoInkTint()
            .font(.caption.weight(.semibold))
            .accessibilityIdentifier("onboarding-how-\(guide.rawValue)")
    }

    private func option(
        _ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey,
        @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack(spacing: GanchoTokens.Spacing.sm) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(GanchoTokens.Palette.accentInk)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, GanchoTokens.Spacing.sm)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.md))
    }

    private var pasteBar: some View {
        VStack(spacing: GanchoTokens.Spacing.xs) {
            Text("Try Paste now")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            // The system control draws its own "Paste" label; the tap grants one read.
            PasteControlView { providers in
                Task { @MainActor in
                    if let saved = await model.ingestAwaitingRow(providers: providers) {
                        onSaved(saved)
                    }
                }
            }
            .frame(width: 160, height: 48)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("onboarding-paste-control")
            .accessibilityLabel(Text("Paste into Gancho"))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, GanchoTokens.Spacing.xs)
        .padding(.bottom, GanchoTokens.Spacing.sm)
        .background(.bar)
    }
}

enum IOSOnboardingGuide: String, Identifiable {
    case keyboard, widget
    var id: String { rawValue }
}

/// Step-by-step set-up for an extension, without leaving the app.
struct IOSOnboardingGuideSheet: View {
    let guide: IOSOnboardingGuide
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    Label {
                        Text(step)
                    } icon: {
                        Text(verbatim: "\(index + 1)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(GanchoTokens.Palette.accentInk)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .accessibilityIdentifier("onboarding-guide-\(guide.rawValue)")
    }

    private var title: Text {
        switch guide {
        case .keyboard: Text("Gancho keyboard")
        case .widget: Text("Home Screen widget")
        }
    }

    private var steps: [LocalizedStringKey] {
        switch guide {
        case .keyboard:
            [
                "Open Settings › General › Keyboard › Keyboards.",
                "Tap Add New Keyboard… and choose Gancho.",
                "Tap Gancho and turn on Allow Full Access, so the keyboard can read your saved clips.",
                "In any text field, hold 🌐 and pick Gancho."
            ]
        case .widget:
            [
                "Touch and hold an empty spot on your Home Screen until the apps jiggle.",
                "Tap Edit, then Add Widget.",
                "Search for Gancho and choose Recent Clips.",
                "Tap a clip in the widget to open it, or Save to keep what you copied."
            ]
        }
    }
}
