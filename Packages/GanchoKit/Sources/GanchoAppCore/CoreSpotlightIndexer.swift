#if canImport(CoreSpotlight)
    import CoreSpotlight
    import Foundation
    import UniformTypeIdentifiers

    /// The system-index adapter behind `LibrarySpotlightService`. All Gancho
    /// donations live in ONE domain, so wiping and replacing the curated set
    /// is a single bounded operation and nothing Gancho ever donated can
    /// outlive a reconcile.
    ///
    /// The planning spec sketched App Intents' `IndexedEntity`; this uses
    /// `CSSearchableItem` directly instead: identifiers stay the clip UUIDs
    /// (so the Spotlight-open path needs no mapping table), the domain wipe is
    /// explicit, and the same code serves macOS and iOS. The Shortcuts-facing
    /// `ClipEntity` remains a plain `AppEntity` — raw history is still never
    /// donated anywhere.
    public struct CoreSpotlightIndexer: SpotlightIndexing {
        public static let domain = "com.johnny4young.gancho.curated-library"

        public init() {}

        public func replaceAll(with entries: [SpotlightEntry]) async throws {
            let index = CSSearchableIndex.default()
            try await index.deleteSearchableItems(withDomainIdentifiers: [Self.domain])
            guard !entries.isEmpty else { return }
            let items = entries.map { entry -> CSSearchableItem in
                let attributes = CSSearchableItemAttributeSet(contentType: .text)
                attributes.title = entry.title
                attributes.contentDescription = entry.summary
                attributes.keywords = [entry.kindLabel]
                return CSSearchableItem(
                    uniqueIdentifier: entry.id.uuidString,
                    domainIdentifier: Self.domain,
                    attributeSet: attributes)
            }
            try await index.indexSearchableItems(items)
        }

        public func removeAll() async throws {
            try await CSSearchableIndex.default()
                .deleteSearchableItems(withDomainIdentifiers: [Self.domain])
        }
    }
#endif
