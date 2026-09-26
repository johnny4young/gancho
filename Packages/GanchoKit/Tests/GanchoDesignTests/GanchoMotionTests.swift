import SwiftUI
import Testing

@testable import GanchoDesign

@Suite("GanchoMotion — Reduce Motion turns every curve off")
struct GanchoMotionTests {
    @Test("Both curves are returned as-is when motion is allowed")
    func allowed() {
        #expect(
            GanchoMotion.animation(GanchoMotion.quick, reduceMotion: false) == GanchoMotion.quick)
        #expect(
            GanchoMotion.animation(GanchoMotion.smooth, reduceMotion: false) == GanchoMotion.smooth)
    }

    @Test("Reduce Motion yields no animation at all")
    func reduced() {
        #expect(GanchoMotion.animation(GanchoMotion.quick, reduceMotion: true) == nil)
        #expect(GanchoMotion.animation(GanchoMotion.smooth, reduceMotion: true) == nil)
    }
}
