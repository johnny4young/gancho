import GanchoAppCore
import GanchoDesign
import SwiftUI

struct MigrationImportHeader: View {
    var body: some View {
        HStack(spacing: GanchoTokens.Spacing.sm) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.title2)
                .foregroundStyle(GanchoTokens.Palette.accent)
                .frame(width: 38, height: 38)
                .background(
                    GanchoTokens.Palette.accent.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Import clipboard history")
                    .font(.headline)
                Text("Preview first. Nothing changes until you approve the import.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(GanchoTokens.Spacing.md)
    }
}

struct MigrationImportSourceChoice: View {
    let chooseMaccy: () -> Void
    let chooseCSV: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.md) {
            Text("Choose a source")
                .font(.title3.bold())
            HStack(spacing: GanchoTokens.Spacing.sm) {
                sourceButton(
                    title: "Maccy database",
                    detail: "Choose Maccy’s Storage.sqlite file.",
                    symbol: "externaldrive.fill",
                    identifier: "migration-select-maccy",
                    action: chooseMaccy)
                sourceButton(
                    title: "CSV file",
                    detail: "Requires text; title and pinned are optional.",
                    symbol: "tablecells.fill",
                    identifier: "migration-select-csv",
                    action: chooseCSV)
            }
            Label(
                "Nothing is uploaded. Gancho reads the selected source only after you approve it.",
                systemImage: "lock.shield.fill"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(GanchoTokens.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            Spacer(minLength: 0)
        }
        .padding(GanchoTokens.Spacing.lg)
    }

    private func sourceButton(
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        symbol: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(GanchoTokens.Palette.accent)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Label("Choose…", systemImage: "arrow.right.circle.fill")
                    .font(.callout.weight(.semibold))
            }
            .padding(GanchoTokens.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .ganchoSurface(radius: GanchoTokens.Radius.md)
        .accessibilityIdentifier(identifier)
    }
}

struct MigrationImportProgress: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(spacing: GanchoTokens.Spacing.md) {
            ProgressView()
                .controlSize(.large)
            Text(title)
                .font(.title3.bold())
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .padding(GanchoTokens.Spacing.lg)
    }
}

struct MigrationImportReview: View {
    let plan: ClipMigrationCoordinator.Plan

    var body: some View {
        let preview = plan.preview
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review before importing")
                        .font(.title3.bold())
                    Text(preview.sourceName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("Dry run complete")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, GanchoTokens.Spacing.sm)
                    .padding(.vertical, GanchoTokens.Spacing.xxs)
                    .background(.green.opacity(0.12), in: Capsule())
            }
            HStack(spacing: GanchoTokens.Spacing.xs) {
                statistic(
                    preview.readyCount, label: "Ready", symbol: "checkmark.circle.fill",
                    tint: .green, identifier: "migration-ready-count")
                statistic(
                    preview.duplicateCount, label: "Duplicates", symbol: "equal.circle.fill",
                    tint: .blue, identifier: "migration-duplicate-count")
                statistic(
                    preview.unsupportedCount, label: "Unsupported", symbol: "minus.circle.fill",
                    tint: .orange, identifier: "migration-unsupported-count")
                statistic(
                    preview.protectedCount, label: "Protected", symbol: "lock.circle.fill",
                    tint: .red, identifier: "migration-protected-count")
            }
            Label(
                "Protected items keep Gancho’s masking and expiry rules.",
                systemImage: "hand.raised.fill"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            Text("No history has changed. Duplicates will stay exactly as they are.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(GanchoTokens.Spacing.lg)
    }

    private func statistic(
        _ value: Int,
        label: LocalizedStringKey,
        symbol: String,
        tint: Color,
        identifier: String
    ) -> some View {
        VStack(spacing: GanchoTokens.Spacing.xxs) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(verbatim: "\(value)")
                .font(.title2.bold().monospacedDigit())
                .accessibilityIdentifier(identifier)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, GanchoTokens.Spacing.sm)
        .ganchoSurface(radius: GanchoTokens.Radius.sm)
    }
}

struct MigrationImportCompletion: View {
    let summary: ClipMigrationCoordinator.Summary

    var body: some View {
        VStack(spacing: GanchoTokens.Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("Memory ready")
                .font(.title2.bold())
                .accessibilityIdentifier("migration-complete-title")
            HStack(spacing: GanchoTokens.Spacing.lg) {
                resultValue(
                    summary.importedCount, label: "Imported",
                    identifier: "migration-imported-count")
                resultValue(
                    summary.skippedDuplicates, label: "Duplicates skipped",
                    identifier: "migration-skipped-count")
                resultValue(
                    summary.protectedCount, label: "Protected",
                    identifier: "migration-imported-protected-count")
            }
            Text("Your source was read-only and remains unchanged.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if summary.unsupportedCount > 0 {
                Text("Unsupported representations were left in the source.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(GanchoTokens.Spacing.lg)
    }

    private func resultValue(
        _ value: Int,
        label: LocalizedStringKey,
        identifier: String
    ) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: "\(value)")
                .font(.title.bold().monospacedDigit())
                .accessibilityIdentifier(identifier)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct MigrationImportFailure: View {
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: GanchoTokens.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 42))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Couldn’t read this source")
                .font(.title3.bold())
                .accessibilityIdentifier("migration-error")
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(GanchoTokens.Spacing.lg)
    }
}
