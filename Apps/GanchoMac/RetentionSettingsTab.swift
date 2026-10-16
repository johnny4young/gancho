import GanchoDesign
import GanchoKit
import SwiftUI

struct RetentionSettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("History") {
                Picker("Keep history for", selection: $model.retentionPolicy.global) {
                    windowOptions
                }
                Picker(
                    "Images", selection: perKindBinding(.image)
                ) { windowOptionsWithDefault }
                Picker(
                    "Text", selection: perKindBinding(.text)
                ) { windowOptionsWithDefault }
                Text(
                    // swiftlint:disable:next line_length
                    "A per-type limit overrides the global window; leave a type on Use global to follow it. Pinned clips and boards never expire."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("Sensitive items") {
                Picker(
                    "Sensitive items expire after",
                    selection: $model.retentionPolicy.sensitiveLifetime
                ) {
                    Text("5 minutes").tag(TimeInterval(300))
                    Text("10 minutes").tag(TimeInterval(600))
                    Text("30 minutes").tag(TimeInterval(1800))
                }
                Label(
                    // swiftlint:disable:next line_length
                    "Detected secrets — passwords, keys, cards — always follow this limit, even when your history keeps everything longer. It's a safety guard you can shorten but not extend.",
                    systemImage: "lock.shield"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(GanchoTokens.Spacing.md)
    }

    @ViewBuilder private var windowOptions: some View {
        Text("24 hours").tag(RetentionPolicy.Window.day)
        Text("7 days").tag(RetentionPolicy.Window.week)
        Text("30 days").tag(RetentionPolicy.Window.month)
        Text("90 days").tag(RetentionPolicy.Window.quarter)
        Text("6 months").tag(RetentionPolicy.Window.halfYear)
        Text("1 year").tag(RetentionPolicy.Window.year)
        Text("Forever").tag(RetentionPolicy.Window.never)
    }

    @ViewBuilder private var windowOptionsWithDefault: some View {
        Text("Use global").tag(RetentionPolicy.Window?.none)
        Text("24 hours").tag(RetentionPolicy.Window?.some(.day))
        Text("7 days").tag(RetentionPolicy.Window?.some(.week))
        Text("30 days").tag(RetentionPolicy.Window?.some(.month))
        Text("90 days").tag(RetentionPolicy.Window?.some(.quarter))
        Text("6 months").tag(RetentionPolicy.Window?.some(.halfYear))
        Text("1 year").tag(RetentionPolicy.Window?.some(.year))
    }

    private func perKindBinding(_ kind: ClipContentKind) -> Binding<RetentionPolicy.Window?> {
        Binding(
            get: { model.retentionPolicy.perKind[kind] },
            set: { model.retentionPolicy.perKind[kind] = $0 })
    }
}
