import Foundation

/// Explicit pin mutation requested by a system surface.
public enum ClipPinAction: Sendable, Equatable {
    case pin
    case unpin
}

/// Complete, content-free outcome set for pinning from App Intents.
public enum ClipPinResult: Sendable, Equatable {
    case pinned
    case unpinned
    case alreadyPinned
    case alreadyUnpinned
    case freeLimitReached
    case clipUnavailable
}

/// Shared pinning command. The caller supplies the authoritative entitlement;
/// this layer owns existence checks, idempotence, and free-tier enforcement.
public enum ClipPinning {
    public static func perform<Store>(
        _ action: ClipPinAction,
        clipID: UUID,
        tier: UserTier,
        store: Store
    ) async throws -> ClipPinResult
    where
        Store: ClipReading & ClipMutating & StoreStatsProviding
    {
        guard let item = try await store.items(ids: [clipID]).first else {
            return .clipUnavailable
        }

        switch action {
        case .pin:
            guard !item.isPinned else { return .alreadyPinned }
            let pinCount = try await store.pinnedCount()
            guard PinLimits.canPin(currentPinCount: pinCount, isPro: tier == .pro) else {
                return .freeLimitReached
            }
            try await store.setPinned(id: clipID, true)
            return .pinned
        case .unpin:
            guard item.isPinned else { return .alreadyUnpinned }
            try await store.setPinned(id: clipID, false)
            return .unpinned
        }
    }
}
