import GRDB

extension GRDBClipboardStore {
    public func existingImportContentHashes(
        _ hashes: Set<String>
    ) async throws -> Set<String> {
        guard !hashes.isEmpty else { return [] }
        let proposed = Array(hashes)
        return try await writer.read { database in
            var existing: Set<String> = []
            // Stay below SQLite's host-parameter limit for large migration
            // previews while keeping the query metadata-only and indexed.
            for chunk in Self.importChunks(proposed) {
                existing.formUnion(try Self.fetchExistingImportHashes(chunk, from: database))
            }
            return existing
        }
    }

    public func importTextBatch(
        _ records: [ClipImportBatchItem]
    ) async throws -> ClipImportBatchResult {
        guard !records.isEmpty else { return ClipImportBatchResult() }
        return try await writer.write { database in
            let proposed = records.map(\.item.contentHash)
            var knownHashes: Set<String> = []
            for chunk in Self.importChunks(proposed) {
                knownHashes.formUnion(try Self.fetchExistingImportHashes(chunk, from: database))
            }
            var insertedItems: [ClipItem] = []
            var skippedDuplicates = 0

            for record in records {
                try Task.checkCancellation()
                guard knownHashes.insert(record.item.contentHash).inserted else {
                    skippedDuplicates += 1
                    continue
                }
                var row = ClipRow(item: record.item)
                row.contentText = record.text
                try row.insert(database)
                insertedItems.append(record.item)
            }
            try Task.checkCancellation()
            return ClipImportBatchResult(
                insertedItems: insertedItems,
                skippedDuplicates: skippedDuplicates)
        }
    }

    private static func importChunks(_ hashes: [String]) -> [[String]] {
        stride(from: 0, to: hashes.count, by: 500).map { start in
            Array(hashes[start..<min(start + 500, hashes.count)])
        }
    }

    private static func fetchExistingImportHashes(
        _ hashes: [String],
        from database: Database
    ) throws -> [String] {
        let placeholders = Array(repeating: "?", count: hashes.count).joined(separator: ",")
        return try String.fetchAll(
            database,
            sql: "SELECT DISTINCT contentHash FROM clip WHERE contentHash IN (\(placeholders))",
            arguments: StatementArguments(hashes))
    }
}
