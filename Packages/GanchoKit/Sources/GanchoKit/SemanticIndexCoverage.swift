import Foundation
import GRDB

public struct SemanticIndexCoverage: Sendable, Equatable {
    public let eligible: Int
    public let indexed: Int
    public var isComplete: Bool { indexed == eligible }
    public init(eligible: Int, indexed: Int) {
        self.eligible = eligible
        self.indexed = indexed
    }
}

public protocol SemanticIndexProviding: Sendable {
    func semanticIndexCoverage(
        query: ClipSearchQuery, dimension: Int
    ) async throws -> SemanticIndexCoverage
}

extension GRDBClipboardStore: SemanticIndexProviding {
    public func semanticIndexCoverage(
        query: ClipSearchQuery, dimension: Int
    ) async throws -> SemanticIndexCoverage {
        try Task.checkCancellation()
        guard dimension > 0, dimension <= 65_536 else {
            return SemanticIndexCoverage(eligible: 0, indexed: 0)
        }
        let result = try await writer.read { db in
            let scope = Self.semanticScope(query, snippetsOnly: false)
            let sql = """
                SELECT COUNT(*) AS eligible, COUNT(e.clipID) AS indexed FROM clip
                LEFT JOIN clip_embedding e ON e.clipID = clip.id
                  AND e.dimension = ? AND e.modelVersion = ? AND LENGTH(e.vector) = ?
                """ + scope.sql + """
                     AND clip.contentText IS NOT NULL AND clip.contentBlobHash IS NULL
                     AND clip.kind NOT IN (?, ?)
                    """
            var arguments: [any DatabaseValueConvertible] = [
                dimension, EmbeddingModelInfo.currentVersion,
                dimension * MemoryLayout<Float>.stride
            ]
            arguments.append(contentsOf: scope.arguments)
            arguments.append(contentsOf: [
                ClipContentKind.image.rawValue, ClipContentKind.fileReference.rawValue
            ])
            let row = try Row.fetchOne(db, sql: sql, arguments: StatementArguments(arguments))
            return SemanticIndexCoverage(
                eligible: row?["eligible"] ?? 0, indexed: row?["indexed"] ?? 0)
        }
        try Task.checkCancellation()
        return result
    }
}
