import Foundation
import GanchoKit

/// The boards the share sheet offers, written by the app whenever they
/// change. Sealed with the store's content key like inbox deposits, so board
/// names stay inside the encryption boundary; the extension never opens the
/// store.
public struct SharedBoardSnapshot: Sendable {
    private let file: URL
    private let key: Data

    init(file: URL, key: Data) {
        self.file = file
        self.key = key
    }

    public static func inAppGroup(key: Data) -> SharedBoardSnapshot? {
        guard
            let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: SharedInbox.appGroupID)
        else { return nil }
        return SharedBoardSnapshot(
            file: container.appendingPathComponent("boards.sealed"), key: key)
    }

    public func write(_ boards: [Pinboard]) throws {
        let sealed = try SealedEnvelope.seal(JSONEncoder().encode(boards), key: key)
        #if os(iOS)
            try sealed.write(
                to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
            try sealed.write(to: file, options: .atomic)
        #endif
    }

    /// The last written boards, or none when there is no readable snapshot.
    public func read() -> [Pinboard] {
        guard let sealed = try? Data(contentsOf: file),
            let data = try? SealedEnvelope.open(sealed, key: key),
            let boards = try? JSONDecoder().decode([Pinboard].self, from: data)
        else { return [] }
        return boards
    }
}
