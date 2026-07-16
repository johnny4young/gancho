import AppKit
import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI
import UniformTypeIdentifiers

/// Guided, approve-after-preview import sheet for Maccy and generic CSV.
/// Source content remains inside the engine plan; this view renders counters
/// and stable errors only, never candidate text or full file paths.
struct MigrationImportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .choose
    @State private var operation: Task<Void, Never>?
    @State private var appliedUITestSeed = false

    private let coordinator = ClipMigrationCoordinator()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 520, height: 430)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { applyUITestSeedIfRequested() }
        .onDisappear { operation?.cancel() }
    }

    private var header: some View {
        MigrationImportHeader()
            // Scope the sheet anchor to the header. Applying it to the root
            // container replaces every descendant control identifier in AX.
            .accessibilityIdentifier("migration-import-sheet")
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .choose:
            chooseSource
        case .checking:
            progress(
                title: "Checking source…",
                detail: "Counting supported items and duplicates without changing history.")
        case .review(let plan):
            review(plan)
        case .importing:
            progress(
                title: "Importing…",
                detail: "Gancho is applying its normal privacy and deduplication rules.")
        case .complete(let summary):
            completion(summary)
        case .failed(let reason):
            failure(reason)
        }
    }

    private var chooseSource: some View {
        MigrationImportSourceChoice(chooseMaccy: chooseMaccy, chooseCSV: chooseCSV)
    }

    private func progress(title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        MigrationImportProgress(title: title, detail: detail)
    }

    private func review(_ plan: ClipMigrationCoordinator.Plan) -> some View {
        MigrationImportReview(plan: plan)
    }

    private func completion(_ summary: ClipMigrationCoordinator.Summary) -> some View {
        MigrationImportCompletion(summary: summary)
    }

    private func failure(_ reason: FailureReason) -> some View {
        MigrationImportFailure(message: reason.message)
    }

    @ViewBuilder private var footer: some View {
        HStack {
            switch phase {
            case .choose:
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            case .checking, .importing:
                Button("Cancel") { cancelOperation() }
                    .accessibilityIdentifier("migration-cancel")
                Spacer()
            case .review(let plan):
                Button("Cancel") { phase = .choose }
                    .accessibilityIdentifier("migration-cancel")
                Spacer()
                Button("Import") { execute(plan) }
                    .buttonStyle(.borderedProminent)
                    .disabled(plan.preview.readyCount == 0)
                    .accessibilityIdentifier("migration-confirm")
            case .complete:
                Button("Import another") { phase = .choose }
                    .accessibilityIdentifier("migration-reset")
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("migration-done")
            case .failed:
                Button("Back") { phase = .choose }
                    .accessibilityIdentifier("migration-back")
                Spacer()
                Button("Done") { dismiss() }
            }
        }
        .padding(.horizontal, GanchoTokens.Spacing.md)
        .padding(.vertical, GanchoTokens.Spacing.sm)
    }

    private func chooseCSV() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose a CSV export")
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        beginPreview(source: .csv(url))
    }

    private func chooseMaccy() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose Maccy’s Storage.sqlite")
        panel.message = String(localized: "Gancho opens the database read-only.")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        beginPreview(source: .maccy(url))
    }

    private func beginPreview(source: ClipMigrationCoordinator.Source) {
        operation?.cancel()
        phase = .checking
        operation = Task { @MainActor in
            do {
                let document = try await coordinator.load(source)
                try Task.checkCancellation()
                let plan = try await makePlan(document, sourceName: source.displayName)
                try Task.checkCancellation()
                phase = .review(plan)
            } catch is CancellationError {
                phase = .choose
            } catch {
                phase = .failed(FailureReason(error))
            }
        }
    }

    private func beginPreview(
        document: ClipImporter.Document,
        sourceName: String
    ) {
        operation?.cancel()
        phase = .checking
        operation = Task { @MainActor in
            do {
                let plan = try await makePlan(document, sourceName: sourceName)
                try Task.checkCancellation()
                phase = .review(plan)
            } catch is CancellationError {
                phase = .choose
            } catch {
                phase = .failed(FailureReason(error))
            }
        }
    }

    private func makePlan(
        _ document: ClipImporter.Document,
        sourceName: String
    ) async throws -> ClipMigrationCoordinator.Plan {
        try await coordinator.preview(
            document,
            sourceName: sourceName,
            configuration: .init(
                sensitiveLifetime: model.retentionPolicy.sensitiveLifetime,
                detectSecrets: model.intelligence.detectSecrets),
            store: model.migrationStore)
    }

    private func execute(_ plan: ClipMigrationCoordinator.Plan) {
        operation?.cancel()
        phase = .importing
        operation = Task { @MainActor in
            do {
                let summary = try await coordinator.execute(
                    plan,
                    store: model.migrationStore,
                    syncEngine: model.syncController.engine)
                await model.refreshRecents()
                phase = .complete(summary)
            } catch is CancellationError {
                phase = .choose
            } catch {
                phase = .failed(.unknown)
            }
        }
    }

    private func cancelOperation() {
        operation?.cancel()
        operation = nil
        phase = .choose
    }

    private func applyUITestSeedIfRequested() {
        #if DEBUG
            guard !appliedUITestSeed,
                model.storageIsEphemeral,
                CommandLine.arguments.contains("-seed-migration-preview")
                    || CommandLine.arguments.contains("-seed-migration-error")
            else { return }
            appliedUITestSeed = true
            if CommandLine.arguments.contains("-seed-migration-error") {
                phase = .failed(.unexpectedMaccySchema)
                return
            }
            beginPreview(
                document: .init(
                    candidates: [
                        .init(text: "Migration sample", title: "Sample", isPinned: true),
                        .init(text: "Migration sample"),
                        .init(text: "https://example.com/docs"),
                        .init(text: "OPENAI_API_KEY=sk-abcdefghijklmnopqrstuvwxyz123456")
                    ],
                    unsupportedCount: 2),
                sourceName: "Migration preview.csv")
        #endif
    }
}

extension MigrationImportView {
    private enum Phase {
        case choose
        case checking
        case review(ClipMigrationCoordinator.Plan)
        case importing
        case complete(ClipMigrationCoordinator.Summary)
        case failed(FailureReason)
    }

    private enum FailureReason {
        case notUTF8
        case emptyCSV
        case missingTextColumn
        case unclosedQuotedField
        case cannotOpenCSVFile
        case cannotOpenMaccyDatabase
        case unexpectedMaccySchema
        case unknown

        init(_ error: any Error) {
            guard case ClipImporter.ImportError.unreadable(let reason) = error else {
                self = .unknown
                return
            }
            self =
                switch reason {
                case .notUTF8: .notUTF8
                case .emptyCSV: .emptyCSV
                case .missingTextColumn: .missingTextColumn
                case .unclosedQuotedField: .unclosedQuotedField
                case .cannotOpenCSVFile: .cannotOpenCSVFile
                case .cannotOpenMaccyDatabase: .cannotOpenMaccyDatabase
                case .unexpectedMaccySchema: .unexpectedMaccySchema
                }
        }

        var message: LocalizedStringKey {
            switch self {
            case .notUTF8: "The CSV file isn’t valid UTF-8."
            case .emptyCSV: "The CSV file is empty."
            case .missingTextColumn: "The CSV header needs a text column."
            case .unclosedQuotedField: "The CSV contains an unfinished quoted field."
            case .cannotOpenCSVFile: "Gancho couldn’t open the selected CSV file."
            case .cannotOpenMaccyDatabase: "Gancho couldn’t open the selected Maccy database."
            case .unexpectedMaccySchema: "This file doesn’t contain a supported Maccy history."
            case .unknown: "The import stopped safely before making changes."
            }
        }
    }
}
