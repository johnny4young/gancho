import ClipboardCore
import GanchoAI
import GanchoDesign
import GanchoKit
import GanchoTelemetry
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WidgetKit

struct IOSSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(IOSAppModel.self) private var model
    @State private var exportDocument: GanchoArchiveDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var transferNote: String?
    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.system.rawValue

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ProInfoView()
                    } label: {
                        Label("Gancho Pro", systemImage: "star")
                    }
                    .accessibilityIdentifier("open-pro")
                    NavigationLink {
                        IOSIntelligenceView()
                    } label: {
                        Label("Intelligence", systemImage: "sparkles")
                    }
                    .accessibilityIdentifier("open-intelligence")
                    NavigationLink {
                        IOSPrivacyCenterView()
                    } label: {
                        Label("Privacy Center", systemImage: "lock.shield")
                    }
                    .accessibilityIdentifier("open-privacy-center")
                }
                Section("Language") {
                    Picker("Language", selection: $appLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(verbatim: language.displayName).tag(language.rawValue)
                        }
                    }
                    .accessibilityIdentifier("language-picker")
                }
                Section("Capture on iPhone") {
                    Text(
                        // swiftlint:disable:next line_length
                        "Gancho never reads your pasteboard in the background. Capture happens only when you act: the save button, the share sheet, or a Shortcut."
                    )
                    .font(.footnote)
                }
                Section("Shortcuts") {
                    Link(destination: URL(string: "https://gancho.app/shortcuts")!) {
                        Label("Example Shortcuts gallery", systemImage: "square.stack.3d.up")
                    }
                }
                Section("Your history") {
                    Toggle(
                        "Show snippets and pins in Spotlight",
                        isOn: Binding(
                            get: { model.spotlightIndexing },
                            set: { model.spotlightIndexing = $0 }))
                    Text(
                        """
                        Only snippets and pinned clips reach the system index — never your \
                        raw history, secrets, or expiring clips. Turning this off removes \
                        them from Spotlight immediately.
                        """
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    Button {
                        startBackup()
                    } label: {
                        Label("Back up history…", systemImage: "arrow.down.doc")
                    }
                    .accessibilityIdentifier("backup-history")
                    Button {
                        showImporter = true
                    } label: {
                        Label("Restore from backup…", systemImage: "arrow.up.doc")
                    }
                    .accessibilityIdentifier("restore-history")
                    Text("Backups are .ganchoarchive files on your device — never uploaded.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let transferNote {
                        Text(verbatim: transferNote)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                #if DEBUG
                    Section {
                        Toggle(
                            isOn: Binding(
                                get: { UserDefaults.standard.bool(forKey: "gancho-force-pro") },
                                set: { model.setDebugForcePro($0) })
                        ) {
                            Text(verbatim: "Force Pro (QA)")
                        }
                        .accessibilityIdentifier("debug-force-pro")
                        Button {
                            model.resetSyncAndRepull()
                        } label: {
                            Text(verbatim: "Reset & re-pull sync")
                        }
                        .accessibilityIdentifier("debug-reset-sync")
                    } header: {
                        Text(verbatim: "Debug")
                    }
                #endif
            }
            .navigationTitle(Text("Settings"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileExporter(
                isPresented: $showExporter, document: exportDocument, contentType: .folder,
                defaultFilename: "gancho-backup.ganchoarchive"
            ) { result in
                if case .failure = result {
                    transferNote = String(localized: "Couldn’t save the backup.")
                }
                exportDocument = nil
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder]) { result in
                guard case .success(let url) = result else { return }
                Task {
                    if let summary = await model.restoreBackup(from: url) {
                        transferNote = String(
                            localized:
                                "Restored \(summary.inserted) clips (\(summary.skippedDuplicates) already here)."
                        )
                    } else {
                        transferNote = String(localized: "That backup couldn’t be restored.")
                    }
                }
            }
        }
    }

    /// Build the .ganchoarchive in a temp dir, then hand it to the system
    /// exporter — the file lands wherever the user picks in Files. Off-device
    /// only if THEY choose an off-device location.
    private func startBackup() {
        Task {
            guard let url = await model.makeBackupArchive(),
                let document = try? GanchoArchiveDocument(directory: url)
            else {
                transferNote = String(localized: "Couldn’t prepare the backup.")
                return
            }
            exportDocument = document
            showExporter = true
        }
    }
}

/// Wraps a `.ganchoarchive` directory as a single document so `fileExporter`
/// can write it out (and macOS can read it back). Stores the URL (Sendable) and
/// builds the directory `FileWrapper` lazily at write time — the format is a
/// directory of clips.json, manifest.json, and the blobs. Export-only; restore
/// goes through `fileImporter`, so the read path is never exercised.
struct GanchoArchiveDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.folder]

    private let directory: URL

    init(directory url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        directory = url
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: directory)
    }
}
