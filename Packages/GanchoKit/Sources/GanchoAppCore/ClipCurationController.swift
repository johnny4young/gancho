import GanchoKit

/// Shared policy and mutation ordering for the two signature curation actions:
/// pinning a clip and promoting it into the snippet library.
///
/// The platform shells retain presentation: paywalls, diagnostics, confirmation
/// feedback, and list refreshes. This controller owns the free-tier decisions,
/// durable mutation, and immediate pin-sync enqueue so macOS, iOS, and future
/// shells cannot silently diverge. It is stateless and `Sendable`; store and
/// sync implementations remain injected through their narrow contracts.
public struct ClipCurationController: Sendable {
    /// Content-free result of toggling a clip's pin state.
    public enum PinOutcome: Sendable, Equatable {
        case pinned
        case unpinned
        case alreadyPinned
        case alreadyUnpinned
        case freeLimitReached
        case clipUnavailable
        case failed
    }

    /// Content-free result of promoting a clip into the local snippet library.
    public enum SnippetOutcome: Sendable, Equatable {
        case promoted
        case freeLimitReached
        case clipUnavailable
        case failed
    }

    public init() {}

    /// Toggles the state requested by the caller's snapshot, but resolves the
    /// clip authoritatively through `ClipPinning` before writing. Successful
    /// mutations are enqueued immediately; no-op, blocked, unavailable, and
    /// failed outcomes never enqueue.
    public func togglePin<Store>(
        _ item: ClipItem,
        tier: UserTier,
        store: Store,
        engine: any SyncEngine
    ) async -> PinOutcome
    where Store: ClipReading & ClipMutating & StoreStatsProviding {
        let action: ClipPinAction = item.isPinned ? .unpin : .pin
        let result: ClipPinResult
        do {
            result = try await ClipPinning.perform(
                action, clipID: item.id, tier: tier, store: store)
        } catch {
            return .failed
        }

        switch result {
        case .pinned:
            await engine.enqueue([item])
            return .pinned
        case .unpinned:
            await engine.enqueue([item])
            return .unpinned
        case .alreadyPinned:
            return .alreadyPinned
        case .alreadyUnpinned:
            return .alreadyUnpinned
        case .freeLimitReached:
            return .freeLimitReached
        case .clipUnavailable:
            return .clipUnavailable
        }
    }

    /// Promotes a clip only after the shared free-tier gate allows it. Snippet
    /// status is device-local in the current sync contract, so this mutation
    /// deliberately does not enqueue the clip.
    public func promoteToSnippet<Store>(
        _ item: ClipItem,
        tier: UserTier,
        store: Store
    ) async -> SnippetOutcome where Store: ClipReading & SnippetStoring {
        do {
            guard try await store.item(id: item.id) != nil else { return .clipUnavailable }
            let count = try await store.snippetCount()
            guard
                SnippetLimits.canPromote(
                    currentSnippetCount: count, isPro: tier == .pro)
            else { return .freeLimitReached }
            try await store.promoteToSnippet(id: item.id, title: nil)
            return .promoted
        } catch {
            return .failed
        }
    }
}
