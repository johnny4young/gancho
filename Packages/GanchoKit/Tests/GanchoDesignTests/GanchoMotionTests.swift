import SwiftUI
import Testing

@testable import GanchoDesign

@Suite("GanchoMotion — Reduce Motion keeps state changes, drops travel")
struct GanchoMotionTests {
    @Test("Every token is returned as-is when motion is allowed")
    func allowed() {
        #expect(GanchoMotion.quick(reduceMotion: false) == GanchoMotion.quick)
        #expect(GanchoMotion.smooth(reduceMotion: false) == GanchoMotion.smooth)
        #expect(GanchoMotion.leave(reduceMotion: false) == GanchoMotion.leave)
        #expect(GanchoMotion.pressScale(reduceMotion: false) == GanchoMotion.pressScale)
        #expect(GanchoMotion.usesBlurReplace(reduceMotion: false))
        #expect(GanchoMotion.usesTravel(reduceMotion: false))
    }

    @Test("Reduce Motion: settle is instant, arrive and leave fade, no blur, no press scale")
    func reduced() {
        #expect(GanchoMotion.quick(reduceMotion: true) == nil)
        #expect(GanchoMotion.smooth(reduceMotion: true) == GanchoMotion.fade)
        #expect(GanchoMotion.leave(reduceMotion: true) == GanchoMotion.fade)
        #expect(GanchoMotion.pressScale(reduceMotion: true) == 1)
        #expect(!GanchoMotion.usesBlurReplace(reduceMotion: true))
        #expect(!GanchoMotion.usesTravel(reduceMotion: true))
    }

    @Test("Press shrinks a little, never collapses")
    func pressScale() {
        #expect(GanchoMotion.pressScale < 1 && GanchoMotion.pressScale > 0.9)
    }
}
