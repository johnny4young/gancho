import Foundation

// MARK: - The client contract
//
// `ClipboardStore` (the original protocol) covers only insert/list/delete/
// export, so every real feature — boards, snippets, search, counters — lives
// on `GRDBClipboardStore` extensions and callers downcast to the concrete
// class (`store as? GRDBClipboardStore`) to reach them. These facets carve
// that surface into small, cohesive protocols so callers can hold exactly the
// capability they need and the concrete class stops being the contract.
//
// Rules that keep this file compile-safe and additive:
// - Every requirement copies an EXISTING `GRDBClipboardStore` method signature
//   exactly, minus default argument values (protocols cannot declare them; the
//   conforming method keeps its defaults and still satisfies the requirement —
//   the same pattern `MCPClipStore` already uses for `search(_:limit:)` and
//   `createPinboard(name:sfSymbol:)`).
// - Overlap with `ClipboardStore`/`MCPClipStore`/`SyncLocalStore` requirements
//   is deliberate and legal: one method satisfies all of them.
// - Facets refine `Sendable` to match the store (Swift 6 strict concurrency):
//   an `any ClipReading` must be as freely passable as the store itself.
//
// Deliberately NOT included (rationale, not oversight):
// - `thumbnailURL(for:)` — its "non-nil means the file is plaintext on disk"
//   semantics are an implementation detail of unencrypted stores; clients must
//   use `thumbnailData(for:)`, which works for encrypted and plaintext stores.
// - `recordMCPAccess(_:)` / `recentMCPAccesses(limit:)` — the MCP access-log
//   surface is being reworked alongside `MCPAccess.swift`; freezing it into a
//   facet now would couple this contract to an in-flight API.
// - `setSortIndex(clipID:_:)` — slated for replacement by the SDK-27
//   Reorderable Containers API; not worth freezing.
// - `migrate()`, `vacuum()`'s writer, `blobsForMaintenance` — GRDB-shaped
//   internals that must never become part of a client contract.

// MARK: - Reading

/// Read-only access to clip history: paged metadata lists, single-item
/// fetches, and the one blob-loading call (`content(for:)`).
///
/// The paging split mirrors the store's layout rule: list calls page METADATA
/// only; full content is a separate per-item fetch so blobs never ride along
/// with scrolling. `Sendable` so an `any ClipReading` handle crosses actor
/// boundaries as freely as the store itself.
public protocol ClipReading: Sendable {
    /// Newest first (pins float to the top), ordered by last activity
    /// (`lastUsedAt` falling back to `createdAt`), paged. Non-archived only.
    func items(offset: Int, limit: Int) async throws -> [ClipItem]

    /// Visible metadata for the requested identifiers, in caller order.
    /// Unlike paging, this resolves old entities directly without an arbitrary
    /// recency window. Unknown, deleted, and archived identifiers are omitted.
    func items(ids: [UUID]) async throws -> [ClipItem]

    /// Recent items for the grouped history browse: pinned first, then by
    /// capture time (`createdAt`) descending so date buckets stay contiguous.
    /// Non-archived only; paginates like `items(offset:limit:)`.
    func recentForBrowse(offset: Int, limit: Int) async throws -> [ClipItem]

    /// Single-clip metadata fetch (membership/sensitive checks, deep links)
    /// without paging the blob. `content(for:)` remains the only blob load.
    func item(id: UUID) async throws -> ClipItem?

    /// Full content for paste-back/detail — the only blob-loading call.
    func content(for id: UUID) async throws -> ClipContent?

    /// Visible (non-archived) items — matches what lists show.
    func count() async throws -> Int

    /// Lazy list-row thumbnail BYTES for binary clips; nil for text clips.
    /// Works for both plaintext and encrypted stores (it decodes the small
    /// cached thumbnail, never the full blob once warmed) — the only
    /// thumbnail API in the client contract.
    func thumbnailData(for id: UUID) async throws -> Data?
}

// MARK: - Searching

/// Every search mode over the history: full-text (FTS5 exact/fuzzy), regex,
/// vector similarity, and saved smart-collection rules.
///
/// Sanitization is the implementation's job, never the caller's — no input
/// may break a query (the reliability rule `ClipSearchQuery` documents).
public protocol ClipSearching: Sendable {
    /// Full-text search. Exact/fuzzy run on FTS5 (sanitized MATCH, ranked by
    /// BM25); regex scans the text columns. Filters (kind / source app /
    /// date / board) apply to every mode. Callers pass an explicit `limit`
    /// (the conforming type may default it; protocols cannot).
    func search(_ query: ClipSearchQuery, limit: Int) async throws -> [ClipItem]

    /// Cosine top-K over stored embedding vectors, joined back to visible
    /// clips. `snippetsOnly` scopes the same engine to the Library.
    func semanticSearch(
        queryVector: [Float], topK: Int, snippetsOnly: Bool
    ) async throws -> [ClipItem]

    /// Evaluates a smart-collection rule as a live query (FTS for the text
    /// part) — the collection is always current, never materialized.
    func items(matching rule: SmartCollectionRule, limit: Int) async throws -> [ClipItem]
}

// MARK: - Source apps

/// Content-free source-app discovery for history filters. Kept separate from
/// `ClipSearching` so clients that only execute explicit queries do not gain an
/// unrelated aggregate-enumeration capability.
public protocol SourceAppProviding: Sendable {
    /// Recent apps represented in visible history, ordered by their newest
    /// capture. Returns bundle IDs and aggregate counts only — never content.
    func recentSourceApps(limit: Int) async throws -> [ClipSourceApp]
}

// MARK: - Mutating

/// User-initiated writes to the history: capture/insert, deletion (plain and
/// sync-aware), the panic wipe, and pinning.
///
/// Deliberately excludes enrichment (`ClipEnriching`) and curation
/// (`SnippetStoring`, `BoardStoring`) so a capture surface can hold write
/// access without board/snippet powers.
public protocol ClipMutating: Sendable {
    /// Inserts a clip with its full content. Implementations deduplicate by
    /// `contentHash` (+ source device): re-copying identical content moves
    /// the existing item to the top instead of duplicating it.
    @discardableResult
    func insert(_ item: ClipItem, content: ClipContent?) async throws -> ClipItem

    /// Plain local delete. When sync is active use `deleteForSync(id:now:)`
    /// instead, or the deletion will not propagate to the user's other devices.
    func delete(id: UUID) async throws

    /// Records the deletion as a tombstone AND removes the row, so the
    /// deletion can propagate before the row is forgotten.
    func deleteForSync(id: UUID, now: Date) async throws

    /// Removes every sensitive clip immediately ("Clear Sensitive" intent and
    /// panic actions). Returns how many were removed.
    @discardableResult
    func deleteAllSensitive() async throws -> Int

    /// Pins/unpins a clip. Pins float to the top of every list and are exempt
    /// from retention; pin state syncs (unlike board membership).
    func setPinned(id: UUID, _ pinned: Bool) async throws

    /// Records that a clip was used (pasted/copied): bumps its use counter and
    /// `lastUsedAt` — the signal frecency ranking reads. Deliberately does NOT
    /// flag the clip for re-upload: a sync cycle per paste would be a storm, so
    /// the freshened `lastUsedAt` rides along with the clip's next real change
    /// (accepted, documented drift).
    func recordUse(id: UUID, now: Date) async throws
}

// MARK: - Reuse suggestions

/// The atomic local signal that turns demonstrated reuse into an optional
/// curation suggestion. Kept separate from `ClipMutating`: callers that only
/// need the nudge cannot delete, pin, or rewrite clipboard history.
public protocol ReuseSuggestionProviding: Sendable {
    /// Records one successful reuse and returns the clip only when the updated
    /// counter equals `requiredUses` and the row is eligible for promotion.
    /// Sensitive, archived, and existing-snippet rows always return nil.
    @discardableResult
    func recordUseAndSnippetSuggestion(
        id: UUID, now: Date, requiredUses: Int
    ) async throws -> ClipItem?
}

// MARK: - Enriching

/// Post-capture enrichment writes: titles, OCR text, content edits, and
/// embedding vectors. Split from `ClipMutating` because enrichment runs from
/// background pipelines that should hold no delete/pin powers.
public protocol ClipEnriching: Sendable {
    /// Tier-1 enrichment: sets the title without touching content.
    func updateTitle(id: UUID, title: String) async throws

    /// Tier-1 enrichment writes a generated title only while the authoritative
    /// row is still untitled. Returns whether the guarded write happened, so a
    /// manual title entered while enrichment was running can never be replaced.
    @discardableResult
    func updateTitleIfEmpty(id: UUID, title: String) async throws -> Bool

    /// OCR enrichment for image clips: extracted text lands in the searchable
    /// text column (screenshots become findable) without altering the preview
    /// or the blob.
    func attachExtractedText(id: UUID, text: String) async throws

    /// Edits a non-sensitive, text-backed clip; recomputes the preview and
    /// invalidates its semantic vector. Binary, file-reference, structured
    /// color, and sensitive rows reject the write. The content hash deliberately
    /// stays unchanged: edits are curation, and re-copying the original must
    /// still dedupe to this row.
    func updateClipText(id: UUID, text: String) async throws

    /// Stores (or replaces) a clip's sentence-embedding vector for semantic
    /// search. Embeddings are device-local — they never sync.
    func saveEmbedding(clipID: UUID, vector: [Float]) async throws
}

// MARK: - Boards

/// Boards: user-made collections, a distinct axis from pinning and from the
/// snippet Library. A clip can belong to many boards; board membership rides
/// the clip's sync record while board metadata syncs on its own record.
public protocol BoardStoring: Sendable {
    /// All boards, system (Favorites) first, then by sort order and age.
    func pinboards() async throws -> [Pinboard]

    /// Creates a user board. Callers pass an explicit `sfSymbol` (the
    /// conforming type may default it; protocols cannot).
    @discardableResult
    func createPinboard(name: String, sfSymbol: String) async throws -> Pinboard

    /// Renames a user board. A guarded no-op on system boards (Favorites).
    func renameBoard(id: UUID, name: String) async throws

    /// Replaces a user board's optional visual identity and marks its metadata
    /// for sync. A guarded no-op on system boards (Favorites).
    func updateBoardIdentity(id: UUID, colorHex: String?, emoji: String?) async throws

    /// Deletes a user board; its clips return to plain history (memberships
    /// cascade away, clips are never deleted). No-op on system boards. When
    /// sync is active use `deletePinboardForSync(id:now:)` instead.
    func deletePinboard(id: UUID) async throws

    /// Deletes a board AND records a tombstone so the deletion reaches the
    /// user's other devices; member clips re-upload so their records drop the
    /// dead board id. No-op on the protected Favorites board.
    func deletePinboardForSync(id: UUID, now: Date) async throws

    /// Adds a clip to a board (idempotent). Orthogonal to pinning; marks the
    /// clip for re-upload so membership propagates.
    func assign(clipID: UUID, toBoard boardID: UUID) async throws

    /// Removes a clip from one board; marks the clip for re-upload.
    func unassign(clipID: UUID, fromBoard boardID: UUID) async throws

    /// Adds or removes several clips in one local database transaction and
    /// marks every affected clip for re-upload. Either the entire visible-order
    /// batch commits or none of it does.
    func setBoardMembership(
        clipIDs: [UUID], boardID: UUID, member: Bool
    ) async throws

    /// Removes a clip from every board; marks the clip for re-upload.
    func removeFromAllBoards(clipID: UUID) async throws

    /// The boards a clip belongs to — drives the context-menu checkmarks.
    func boardIDs(forClip clipID: UUID) async throws -> Set<UUID>

    /// One page of a board's members, pinned first, most recently updated
    /// next. Boards are user-curated but unbounded, so every surface reads
    /// them in pages instead of loading the whole set.
    func items(inBoard boardID: UUID, offset: Int, limit: Int) async throws -> [ClipItem]

    /// How many clips a board holds — the board rail/home counters.
    func count(inBoard boardID: UUID) async throws -> Int

    /// Replaces a clip's board membership wholesale (the sync receive path);
    /// unknown board ids get placeholder boards so membership is never lost.
    func setBoardMembership(clipID: UUID, boardIDs: Set<UUID>) async throws
}

// MARK: - Snippets

/// The curated Library: snippets are permanent (exempt from retention and
/// tier archiving), optionally keyword-invoked, and share the clip table so
/// search and dedupe stay unified.
public protocol SnippetStoring: Sendable {
    /// One gesture turns an ephemeral clip into a permanent snippet
    /// (optionally titled — pass nil to keep the current title).
    func promoteToSnippet(id: UUID, title: String?) async throws

    /// Back to plain history (retention applies again).
    func demoteFromSnippet(id: UUID) async throws

    /// Every snippet, most recently updated first.
    func snippets() async throws -> [ClipItem]

    /// Library size — the free-tier promote gate consults this.
    func snippetCount() async throws -> Int

    /// Creates a snippet from scratch (CLI `gancho save` / editor import),
    /// bypassing capture. Callers pass an explicit `language` (nil for none;
    /// the conforming type may default it — protocols cannot).
    @discardableResult
    func saveSnippet(title: String, text: String, language: String?) async throws -> ClipItem

    /// Edits a snippet's title and full text (the editor surface).
    func updateSnippet(id: UUID, title: String, text: String) async throws

    /// Sets (or clears, with nil/blank) a snippet's invocation keyword.
    func setKeyword(id: UUID, keyword: String?) async throws

    /// Bumps the usage counter — call when a snippet is inserted.
    func incrementUses(id: UUID) async throws

    /// The snippet invoked by an exact keyword (case-insensitive), if any —
    /// the keyword-expansion path.
    func snippet(matchingKeyword keyword: String) async throws -> ClipItem?
}

// MARK: - Counters

/// Aggregate counters for the Privacy Center dashboard and the free-tier
/// gates. Numbers only — none of these can carry clip content, by
/// construction (the no-content-logging invariant extends to stats).
public protocol StoreStatsProviding: Sendable {
    /// How many clips are pinned — the free-tier pin gate consults this.
    func pinnedCount() async throws -> Int

    /// How many sensitive clips are currently held — the honest count behind
    /// the Privacy Center's "Secrets masked" stat. Excludes archived rows.
    func sensitiveCount() async throws -> Int

    /// How many clips the free tier has archived (hidden, never deleted) —
    /// the "N older clips come back with Pro" notice.
    func archivedCount() async throws -> Int

    /// How many clips have been uploaded to iCloud — the Privacy Center
    /// "Items synchronized" count.
    func syncedCount() async throws -> Int

    /// Total purged items since a date — the Privacy Center retention counter
    /// (numbers only; the content is gone and was never logged).
    func purgedItemCount(since date: Date) async throws -> Int
}

// MARK: - Private activity receipt

/// Local-only activity aggregates for the first-party Privacy Center. This is
/// deliberately separate from analytics and from `StoreStatsProviding`: it can
/// mutate and clear a bounded receipt, while ordinary current-state counters
/// remain read-only. No third-party client composition includes this facet.
public protocol PrivateActivityReceiptStoring: Sendable {
    /// Adds successful capture events to the source-app/day bucket.
    func recordPrivateCapture(
        sourceAppBundleID: String?, count: Int, at date: Date
    ) async throws

    /// Adds reused items to the target-app/day bucket.
    func recordPrivateReuse(
        targetAppBundleID: String?, itemCount: Int, at date: Date
    ) async throws

    /// Adds skipped captures; protected copies remain an explicit subset.
    func recordPrivateSkippedCapture(
        isProtected: Bool, count: Int, at date: Date
    ) async throws

    /// Adds the number of sensitive items removed by one retention pass.
    func recordPrivateSensitiveExpiry(count: Int, at date: Date) async throws

    /// Reads the rolling receipt, pruning expired day buckets first.
    func privateActivityReceipt(now: Date) async throws -> PrivateActivityReceipt

    /// Erases receipt rows only, leaving clips and configuration untouched.
    func clearPrivateActivityReceipt() async throws
}

// MARK: - Export

/// Whole-history export. Always available, on every tier — no data hostage.
///
/// NOT yet frozen for third-party clients: the `Data`-returning shape
/// materializes the full history in memory and will move to a streaming,
/// URL-returning API before the contract freeze (see the refactor plan);
/// the facet exists now so callers stop depending on the concrete class.
public protocol ExportProviding: Sendable {
    /// Versioned JSON export: full metadata + text content; binary payloads
    /// referenced by content hash. Includes sensitive clips.
    func exportJSON() async throws -> Data

    /// As `exportJSON()`, optionally dropping detector-flagged sensitive
    /// clips — an export must not turn a short-expiry secret into permanent
    /// plaintext unless the caller explicitly opts in.
    func exportJSON(excludeSensitive: Bool) async throws -> Data

    /// RFC-4180 CSV export (formula-injection hardened): metadata + text
    /// content, binaries listed by reference. Includes sensitive clips.
    func exportCSV() async throws -> Data

    /// As `exportCSV()`, optionally dropping detector-flagged sensitive clips.
    func exportCSV(excludeSensitive: Bool) async throws -> Data
}

// MARK: - Maintenance

/// Bulk and housekeeping operations app shells trigger at the edges (import,
/// post-launch backfill, post-purge compaction). Not part of the third-party
/// client contract — a remote client never runs local maintenance.
public protocol StoreMaintaining: Sendable {
    /// Bulk insert in one transaction — importers and synthetic fixtures.
    /// Skips dedupe on purpose (imports are presumed pre-deduplicated).
    func importBatch(_ entries: [(item: ClipItem, content: ClipContent?)]) async throws

    /// One-time cosmetic preview backfill; idempotent. Call from a
    /// post-launch background task, never on the open path.
    func backfillLegacyPreviews() async throws

    /// Reclaims space after large deletes. Runs on the store's writer queue —
    /// never the main thread.
    func vacuum() async throws
}

// MARK: - Compositions

/// The surface a third-party / non-Apple client (the README's future
/// transports) programs against: read, search, boards, and export — no local
/// mutation, enrichment, or maintenance. This is the composition to keep
/// stable; grow it by adding facets, not by widening existing ones.
public typealias GanchoClientStore = ClipReading & ClipSearching & BoardStoring & ExportProviding

/// The full first-party surface the Mac and iOS app models hold in place of the
/// concrete `GRDBClipboardStore`: all twelve facets composed. App code downcasts
/// its `any ClipboardStore` to this ONCE at the composition root
/// (`store as? any FullClipStore`, nil on the in-memory fallback) and reaches
/// every capability through it; only engine construction and MCP/sync internals
/// keep a concrete handle. Grow it by adding facets.
///
/// `ClipboardStore` is intentionally NOT composed in: each of its requirements
/// (`insert`, `count`, `content(for:)`, `delete`, `items(offset:limit:)`,
/// `exportJSON`/`exportCSV`) is already restated by one of the facets, so adding
/// it would only duplicate requirements in the existential. The twelve facets have
/// no overlapping requirements among themselves, so member access on an
/// `any FullClipStore` is unambiguous.
public typealias FullClipStore = ClipReading & ClipSearching & ClipMutating & ClipEnriching
    & SourceAppProviding & ReuseSuggestionProviding & BoardStoring & SnippetStoring
    & StoreStatsProviding & PrivateActivityReceiptStoring & ExportProviding & StoreMaintaining

// MARK: - Production conformances

/// Retroactive (same-module) conformances: every requirement above copies an
/// existing `GRDBClipboardStore` method exactly, so the bodies already exist
/// — these declarations only attach the facet types. Kept in one place so
/// the contract's full production surface is auditable at a glance.
extension GRDBClipboardStore: ClipReading {}
extension GRDBClipboardStore: ClipSearching {}
extension GRDBClipboardStore: SourceAppProviding {}
extension GRDBClipboardStore: ClipMutating {}
extension GRDBClipboardStore: ReuseSuggestionProviding {}
extension GRDBClipboardStore: ClipEnriching {}
extension GRDBClipboardStore: BoardStoring {}
extension GRDBClipboardStore: SnippetStoring {}
extension GRDBClipboardStore: StoreStatsProviding {}
extension GRDBClipboardStore: PrivateActivityReceiptStoring {}
extension GRDBClipboardStore: ExportProviding {}
extension GRDBClipboardStore: StoreMaintaining {}
