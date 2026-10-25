import Foundation
import GanchoKit

/// The Retention timeline: one marker per distinct lifetime, shortest first,
/// "never" last. Equal lifetimes share a marker, a type left on Use global
/// folds into "everything else", and a global of Forever joins "never".
public enum RetentionTimeline {
    public enum Group: String, Sendable, Equatable, CaseIterable {
        case secrets, images, text, everything, keptForever
    }

    public struct Marker: Equatable, Sendable {
        /// Seconds of life; nil is never.
        public let lifetime: TimeInterval?
        public let groups: [Group]
    }

    public static func markers(for policy: RetentionPolicy) -> [Marker] {
        var entries: [(TimeInterval?, Group)] = [(policy.sensitiveLifetime, .secrets)]
        if let images = policy.perKind[.image] { entries.append((images.lifetime, .images)) }
        if let text = policy.perKind[.text] { entries.append((text.lifetime, .text)) }
        entries.append((policy.global.lifetime, .everything))
        entries.append((nil, .keptForever))

        var markers: [Marker] = []
        for (lifetime, group) in entries {
            if let index = markers.firstIndex(where: { $0.lifetime == lifetime }) {
                let marker = markers[index]
                markers[index] = Marker(lifetime: lifetime, groups: marker.groups + [group])
            } else {
                markers.append(Marker(lifetime: lifetime, groups: [group]))
            }
        }
        return markers.sorted { lhs, rhs in
            switch (lhs.lifetime, rhs.lifetime) {
            case (let left?, let right?): left < right
            case (.some, .none): true
            default: false
            }
        }
    }

    /// Where a marker sits along the track, 0…1: evenly spaced by order.
    public static func position(of index: Int, in count: Int) -> Double {
        count > 1 ? Double(index) / Double(count - 1) : 0
    }
}

/// "Forget recent clips": how far back a recent forget reaches.
public enum ForgetRecentWindow: Int, CaseIterable, Identifiable, Sendable {
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case hour = 60

    public var id: Int { rawValue }

    public func cutoff(now: Date = .now) -> Date {
        now.addingTimeInterval(-Double(rawValue) * 60)
    }
}
