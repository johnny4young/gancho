import Foundation
import GanchoKit

/// A clip dragged inside the app onto a board. The drag carries only the
/// clip's id; everything else is read back from the store at drop time.
public enum BoardDrop {
    public enum Decision: Equatable, Sendable {
        case add
        /// Already filed there: say so, write nothing.
        case alreadyMember
        /// Gone, being deleted, expired or protected: nothing happens.
        case ignore
    }

    public static func decide(
        item: ClipItem?, isMember: Bool, isPendingDeletion: Bool, now: Date = .now
    ) -> Decision {
        guard let item, !isPendingDeletion, !ClipSafePresentation.requiresMasking(item),
            item.expiresAt.map({ $0 > now }) ?? true
        else { return .ignore }
        return isMember ? .alreadyMember : .add
    }

    public static func payload(for id: UUID) -> Data {
        Data(id.uuidString.utf8)
    }

    public static func clipID(from payload: Data) -> UUID? {
        String(data: payload, encoding: .utf8).flatMap(UUID.init(uuidString:))
    }
}
