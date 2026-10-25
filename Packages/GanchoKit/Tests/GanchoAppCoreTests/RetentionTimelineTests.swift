import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

@Suite("Retention timeline — one marker per lifetime, shortest first")
struct RetentionTimelineTests {
    @Test("Defaults: secrets, everything else, then never")
    func defaults() {
        let policy = RetentionPolicy(global: .month, sensitiveLifetime: 600)
        let markers = RetentionTimeline.markers(for: policy)
        let lifetimes: [TimeInterval?] = [600, RetentionPolicy.Window.month.lifetime, nil]
        let groups: [[RetentionTimeline.Group]] = [[.secrets], [.everything], [.keptForever]]
        #expect(markers.map(\.lifetime) == lifetimes)
        #expect(markers.map(\.groups) == groups)
    }

    @Test("Each picker moves its own marker; Use global folds into everything else")
    func perKind() {
        var policy = RetentionPolicy(global: .month, sensitiveLifetime: 600)
        policy.perKind[.image] = .week
        policy.perKind[.text] = .year
        let markers = RetentionTimeline.markers(for: policy)
        let ordered: [[RetentionTimeline.Group]] = [
            [.secrets], [.images], [.everything], [.text], [.keptForever]
        ]
        #expect(markers.map(\.groups) == ordered)
        policy.perKind[.image] = nil
        #expect(!RetentionTimeline.markers(for: policy).flatMap(\.groups).contains(.images))
    }

    @Test("Equal lifetimes share a marker; a Forever global joins never")
    func merging() {
        var policy = RetentionPolicy(global: .never, sensitiveLifetime: 300)
        policy.perKind[.image] = .never
        let markers = RetentionTimeline.markers(for: policy)
        #expect(markers.count == 2)
        #expect(markers.last?.lifetime == nil)
        let forever: [RetentionTimeline.Group] = [.images, .everything, .keptForever]
        #expect(markers.last?.groups == forever)
    }

    @Test("Markers spread evenly by order")
    func positions() {
        #expect(RetentionTimeline.position(of: 0, in: 4) == 0)
        #expect(RetentionTimeline.position(of: 3, in: 4) == 1)
        #expect(RetentionTimeline.position(of: 1, in: 3) == 0.5)
        #expect(RetentionTimeline.position(of: 0, in: 1) == 0)
    }

    @Test("A recent forget reaches back exactly its window")
    func forgetWindow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(ForgetRecentWindow.fifteenMinutes.cutoff(now: now) == now.addingTimeInterval(-900))
        #expect(ForgetRecentWindow.allCases.map(\.rawValue) == [5, 15, 60])
    }
}
