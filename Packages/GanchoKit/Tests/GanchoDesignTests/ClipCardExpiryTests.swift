import Foundation
import GanchoKit
import Testing

@testable import GanchoDesign

@Suite("ClipCard — expiry countdown threshold")
struct ClipCardExpiryTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("No expiry → no countdown")
    func noExpiry() {
        #expect(ClipCard.showsExpiryCountdown(expiresAt: nil, now: now) == false)
    }

    @Test("Within the hour → countdown")
    func withinHour() {
        #expect(
            ClipCard.showsExpiryCountdown(
                expiresAt: now.addingTimeInterval(59 * 60), now: now) == true)
        #expect(
            ClipCard.showsExpiryCountdown(
                expiresAt: now.addingTimeInterval(30), now: now) == true)
    }

    @Test("An hour or more away → no countdown yet")
    func beyondHour() {
        #expect(
            ClipCard.showsExpiryCountdown(
                expiresAt: now.addingTimeInterval(3600), now: now) == false)
        #expect(
            ClipCard.showsExpiryCountdown(
                expiresAt: now.addingTimeInterval(2 * 3600), now: now) == false)
    }

    @Test("Already expired → no countdown")
    func alreadyPast() {
        #expect(
            ClipCard.showsExpiryCountdown(
                expiresAt: now.addingTimeInterval(-1), now: now) == false)
    }
}
