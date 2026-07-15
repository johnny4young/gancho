import Foundation
import GanchoKit
import Observation

/// The local-only usage signals attached to a successful clip reuse.
/// Search queries remain device-local and can be erased independently from
/// history; implementations must never sync or log them.
public protocol ReuseUsageStoring: ReuseSuggestionProviding {
    func recordSearch(_ query: String, now: Date) async throws
    func recentSearches(limit: Int) async throws -> [String]
    func clearSearchHistory() async throws
}

extension GRDBClipboardStore: ReuseUsageStoring {}

/// Owns a macOS reuse session without owning platform presentation: the recent
/// page, successful-search signals, cyclic selection, paste-stack ordering, and
/// the reversible-delete window. AppKit paste-back, toasts, telemetry, and the
/// concrete sync action remain injected shell effects.
///
/// Keeping this boundary on store capabilities and closures makes the ordering
/// testable without windows, accessibility privileges, or CloudKit. Explicit
/// main-actor isolation preserves the execution context this state had in
/// `AppModel` while still allowing asynchronous store actors underneath it.
@Observable
@MainActor
public final class ReuseController {
    public private(set) var recentItems: [ClipItem] = []
    public var activeSearchQuery = ""

    public var rememberSearches: Bool {
        didSet {
            onRememberSearchesChanged(rememberSearches)
            guard !rememberSearches, let usageStore else { return }
            Task { try? await usageStore.clearSearchHistory() }
        }
    }

    private var stack = PasteStack()
    @ObservationIgnored private let store: any ClipboardStore
    @ObservationIgnored private let usageStore: (any ReuseUsageStoring)?
    @ObservationIgnored private let deletionCoordinator: DeletionCoordinator
    @ObservationIgnored private let onRememberSearchesChanged: @MainActor (Bool) -> Void
    @ObservationIgnored private var onRecentItemsChanged: @MainActor ([ClipItem]) -> Void = { _ in }
    @ObservationIgnored private var cycleIndex = 0
    @ObservationIgnored private var lastCycleAt = Date.distantPast

    public init(
        store: any ClipboardStore,
        usageStore: (any ReuseUsageStoring)?,
        rememberSearches: Bool,
        deletionCoordinator: DeletionCoordinator = DeletionCoordinator(),
        onRememberSearchesChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.store = store
        self.usageStore = usageStore
        self.rememberSearches = rememberSearches
        self.deletionCoordinator = deletionCoordinator
        self.onRememberSearchesChanged = onRememberSearchesChanged
    }

    /// Installs the shell effect that mirrors the newest visible clip to the
    /// menu-bar helper. Kept settable because the AppModel composition root
    /// cannot capture itself until all stored dependencies are initialized.
    public func setRecentItemsObserver(
        _ observer: @escaping @MainActor ([ClipItem]) -> Void
    ) {
        onRecentItemsChanged = observer
    }

    /// Reloads the first metadata page and keeps clips in their undo window
    /// hidden even when an unrelated capture triggers a refresh.
    public func refreshRecents() async {
        let items = (try? await store.items(offset: 0, limit: 50)) ?? []
        updateRecentItems(
            deletionCoordinator.hasPending
                ? items.filter { !deletionCoordinator.isPending($0.id) } : items)
    }

    /// Records the local ranking/search signals after a paste succeeds, moves
    /// the reused item to the top through the store's metadata-only insert, and
    /// reconciles the visible page from the store of record.
    @discardableResult
    public func recordPaste(of item: ClipItem, now: Date = .now) async -> ClipItem? {
        let suggestion = await recordUseAndSnippetSuggestion(for: item, now: now)
        await rememberActiveSearch(now: now)
        _ = try? await store.insert(item, content: nil)
        await refreshRecents()
        return suggestion
    }

    /// A successful drag is a reuse signal but must not reorder the list under
    /// the pointer, so it records usage/search without the metadata insert.
    @discardableResult
    public func recordDragDelivery(of item: ClipItem, now: Date = .now) async -> ClipItem? {
        let suggestion = await recordUseAndSnippetSuggestion(for: item, now: now)
        await rememberActiveSearch(now: now)
        return suggestion
    }

    /// Snippet insertion bumps frecency and refreshes, but it does not consume
    /// the panel's search query or perform a second move-to-top insert.
    public func recordSnippetPaste(of item: ClipItem, now: Date = .now) async {
        _ = await recordUseAndSnippetSuggestion(for: item, now: now)
        await refreshRecents()
    }

    public func recentSearches(limit: Int = 5) async -> [String] {
        (try? await usageStore?.recentSearches(limit: limit)) ?? []
    }

    /// Returns the next history item, wrapping at the end and resetting to the
    /// top after eight seconds without a cycle command.
    public func nextCyclicItem(now: Date = .now) -> ClipItem? {
        if now.timeIntervalSince(lastCycleAt) > 8 { cycleIndex = 0 }
        lastCycleAt = now
        guard !recentItems.isEmpty else { return nil }
        let item = recentItems[cycleIndex % recentItems.count]
        cycleIndex += 1
        return item
    }

    public var pasteStackEntries: [PasteStack.Entry] { stack.entries }

    public func pushToStack(_ item: ClipItem) {
        stack.push(item)
    }

    public func pushToStack(_ items: [ClipItem]) {
        stack.push(contentsOf: items)
    }

    public func clearStack() {
        stack.clear()
    }

    public func removeFromStack(entryID: Int) {
        stack.remove(entryID: entryID)
    }

    public func moveInStack(fromOffsets source: IndexSet, toOffset destination: Int) {
        stack.move(fromOffsets: source, toOffset: destination)
    }

    public func popNextFromStack() -> ClipItem? {
        stack.popFirst()
    }

    /// Hides the row immediately, then lets DeletionCoordinator preserve the
    /// six-second commit/undo ordering. The shell supplies the sync-aware store
    /// mutation; this controller owns the state and post-commit reconciliation.
    @discardableResult
    public func delete(
        _ item: ClipItem,
        performDelete: @escaping @MainActor (UUID) async -> Void
    ) -> DeletionTransaction {
        delete([item]) { ids in
            for id in ids { await performDelete(id) }
        }
    }

    /// Hides a visible-order batch immediately and commits it behind one grace
    /// timer, so the shell can surface exactly one Undo action.
    @discardableResult
    public func delete(
        _ items: [ClipItem],
        performDelete: @escaping @MainActor ([UUID]) async -> Void
    ) -> DeletionTransaction {
        let ids = items.map(\.id)
        let idSet = Set(ids)
        updateRecentItems(recentItems.filter { !idSet.contains($0.id) })
        return deletionCoordinator.beginDeletion(
            ids,
            performDelete: performDelete,
            didFinish: { [weak self] _ in await self?.refreshRecents() })
    }

    public func undoDeletion(_ id: UUID) {
        deletionCoordinator.undo(id) { [weak self] _ in await self?.refreshRecents() }
    }

    public func undoDeletion(_ transaction: DeletionTransaction) {
        deletionCoordinator.undo(transaction) { [weak self] _ in await self?.refreshRecents() }
    }

    public func isDeletionPending(_ id: UUID) -> Bool {
        deletionCoordinator.isPending(id)
    }

    private func rememberActiveSearch(now: Date) async {
        let query = activeSearchQuery
        activeSearchQuery = ""
        guard rememberSearches, !query.isEmpty else { return }
        try? await usageStore?.recordSearch(query, now: now)
    }

    private func recordUseAndSnippetSuggestion(
        for item: ClipItem, now: Date
    ) async -> ClipItem? {
        try? await usageStore?.recordUseAndSnippetSuggestion(
            id: item.id, now: now,
            requiredUses: SnippetLimits.promotionSuggestionUseThreshold)
    }

    private func updateRecentItems(_ items: [ClipItem]) {
        recentItems = items
        onRecentItemsChanged(items)
    }
}
