import ClipboardCore
import Foundation
import GanchoAI
import GanchoKit

/// Owns the approve-after-preview migration workflow: source decoding, normal
/// classification and secret policy, a metadata-only dedupe dry run, and one
/// atomic destination transaction followed by sync enqueue. It imports no UI
/// framework and never logs source paths or clipboard content.
public struct ClipMigrationCoordinator: Sendable {
    /// A user-approved source. Creating this value performs no IO; `load(_:)`
    /// reads only after the file picker has returned approval.
    public enum Source: Sendable, Equatable {
        case csv(URL)
        case maccy(URL)

        /// File name safe to show in the review UI; the full path stays private.
        public var displayName: String {
            switch self {
            case .csv(let url), .maccy(let url): url.lastPathComponent
            }
        }
    }

    /// Privacy settings applied exactly as they are for a new capture.
    public struct Configuration: Sendable, Equatable {
        public var sensitiveLifetime: TimeInterval
        public var detectSecrets: Bool

        public init(sensitiveLifetime: TimeInterval = 600, detectSecrets: Bool = true) {
            self.sensitiveLifetime = sensitiveLifetime
            self.detectSecrets = detectSecrets
        }
    }

    /// Content-free outcome of the dry run shown before any destination write.
    public struct Preview: Sendable, Equatable {
        public var sourceName: String
        public var totalCount: Int
        public var readyCount: Int
        public var duplicateCount: Int
        public var unsupportedCount: Int
        public var protectedCount: Int

        public init(
            sourceName: String,
            totalCount: Int,
            readyCount: Int,
            duplicateCount: Int,
            unsupportedCount: Int,
            protectedCount: Int
        ) {
            self.sourceName = sourceName
            self.totalCount = totalCount
            self.readyCount = readyCount
            self.duplicateCount = duplicateCount
            self.unsupportedCount = unsupportedCount
            self.protectedCount = protectedCount
        }
    }

    /// Opaque approved plan retained in memory between review and confirmation.
    /// Only its content-free preview is public; candidate text never reaches UI.
    public struct Plan: Sendable {
        public let preview: Preview
        fileprivate let records: [ClipImportBatchItem]
        fileprivate let protectedIDs: Set<UUID>
    }

    /// Content-free final result shown after the atomic commit.
    public struct Summary: Sendable, Equatable {
        public var importedCount: Int
        public var skippedDuplicates: Int
        public var unsupportedCount: Int
        public var protectedCount: Int

        public init(
            importedCount: Int,
            skippedDuplicates: Int,
            unsupportedCount: Int,
            protectedCount: Int
        ) {
            self.importedCount = importedCount
            self.skippedDuplicates = skippedDuplicates
            self.unsupportedCount = unsupportedCount
            self.protectedCount = protectedCount
        }
    }

    private let classifier: RuleClassifier
    private let detector: SensitiveDataDetector

    public init(
        classifier: RuleClassifier = RuleClassifier(),
        detector: SensitiveDataDetector = SensitiveDataDetector()
    ) {
        self.classifier = classifier
        self.detector = detector
    }

    /// Decodes a source while holding its sandbox security scope. CSV bytes are
    /// read off the main actor; Maccy's database is opened read-only by the
    /// engine parser. Errors remain stable and content-free.
    public func load(_ source: Source) async throws -> ClipImporter.Document {
        let url: URL
        switch source {
        case .csv(let sourceURL), .maccy(let sourceURL): url = sourceURL
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        switch source {
        case .csv(let url):
            let data: Data
            do {
                data = try await Task.detached(priority: .userInitiated) {
                    try Data(contentsOf: url, options: .mappedIfSafe)
                }.value
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw ClipImporter.ImportError.unreadable(.cannotOpenCSVFile)
            }
            return try ClipImporter.readCSV(data)
        case .maccy(let url):
            return try await ClipImporter.readMaccy(databaseAt: url)
        }
    }

    /// Applies the same classifier and sensitive-ingestion policy as capture,
    /// then compares hashes without loading destination content. Source titles
    /// and pin flags are discarded for protected rows so a foreign field cannot
    /// leak or permanently retain secret material.
    public func preview(
        _ document: ClipImporter.Document,
        sourceName: String,
        configuration: Configuration,
        store: any ClipImporting
    ) async throws -> Plan {
        var prepared: [ClipImportBatchItem] = []
        var protectedCandidateIDs: Set<UUID> = []
        prepared.reserveCapacity(document.candidates.count)

        for candidate in document.candidates {
            try Task.checkCancellation()
            let capture = PasteboardCapture(text: candidate.text)
            var (item, content) = ClipItemFactory.make(
                from: capture,
                classifier: classifier,
                detector: detector,
                sensitiveLifetime: configuration.sensitiveLifetime,
                detectSecrets: configuration.detectSecrets)

            if configuration.detectSecrets,
                let title = candidate.title,
                let titleFinding = detector.detect(title)
            {
                item = SensitiveIngestionPolicy.decorate(
                    item,
                    finding: titleFinding,
                    originalText: candidate.text,
                    sensitiveLifetime: configuration.sensitiveLifetime)
            }

            let isProtected = item.isSensitive || item.kind.prefersMaskedPreview
            if isProtected {
                item.title = ""
                item.isPinned = false
                protectedCandidateIDs.insert(item.id)
            } else {
                item.title = candidate.title.map(Self.normalizedTitle) ?? ""
                item.isPinned = candidate.isPinned
            }
            guard case .text(let text)? = content else { continue }
            prepared.append(ClipImportBatchItem(item: item, text: text))
        }

        let proposedHashes = Set(prepared.map(\.item.contentHash))
        var seenHashes = try await store.existingImportContentHashes(proposedHashes)
        var ready: [ClipImportBatchItem] = []
        var duplicates = 0
        var protectedIDs: Set<UUID> = []
        ready.reserveCapacity(prepared.count)
        for record in prepared {
            if seenHashes.insert(record.item.contentHash).inserted {
                ready.append(record)
                if protectedCandidateIDs.contains(record.item.id) {
                    protectedIDs.insert(record.item.id)
                }
            } else {
                duplicates += 1
            }
        }

        let preview = Preview(
            sourceName: sourceName,
            totalCount: document.candidates.count + document.unsupportedCount,
            readyCount: ready.count,
            duplicateCount: duplicates,
            unsupportedCount: document.unsupportedCount,
            protectedCount: protectedIDs.count)
        return Plan(preview: preview, records: ready, protectedIDs: protectedIDs)
    }

    /// Commits the reviewed rows atomically and enqueues only newly inserted
    /// records after the transaction succeeds. Cancellation rolls back the
    /// store batch; duplicates discovered since preview remain untouched.
    public func execute(
        _ plan: Plan,
        store: any ClipImporting,
        syncEngine: any SyncEngine
    ) async throws -> Summary {
        let result = try await store.importTextBatch(plan.records)
        await syncEngine.enqueue(result.insertedItems)
        let insertedIDs = Set(result.insertedItems.map(\.id))
        return Summary(
            importedCount: result.insertedItems.count,
            skippedDuplicates: plan.preview.duplicateCount + result.skippedDuplicates,
            unsupportedCount: plan.preview.unsupportedCount,
            protectedCount: insertedIDs.intersection(plan.protectedIDs).count)
    }

    private static func normalizedTitle(_ title: String) -> String {
        String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
    }
}
