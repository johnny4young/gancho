import Foundation

/// What a board row can truthfully say about sync: no per-device list is
/// stored, so only whether its last change has reached iCloud.
public enum BoardSyncState: Equatable, Sendable {
    /// Sync is off (Free, or no iCloud): the board lives on this device.
    case onThisDevice
    case waiting
    case synced

    /// `syncHealthy` is false while sync is paused or failing: nothing new is
    /// reaching iCloud then, so no board claims to be synced.
    public init(
        boardID: UUID, syncEnabled: Bool, syncHealthy: Bool = true, awaitingUpload: Set<UUID>
    ) {
        if !syncEnabled {
            self = .onThisDevice
        } else if !syncHealthy || awaitingUpload.contains(boardID) {
            self = .waiting
        } else {
            self = .synced
        }
    }
}
