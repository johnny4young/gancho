import SwiftUI
import Testing

@testable import GanchoDesign

@Suite("GanchoMotion — Reduce Motion turns every curve off")
struct GanchoMotionTests {
    @Test("Both curves are returned as-is when motion is allowed")
    func allowed() {
        #expect(GanchoMotion.quick(reduceMotion: false) == GanchoMotion.quick)
        #expect(GanchoMotion.smooth(reduceMotion: false) == GanchoMotion.smooth)
        #expect(GanchoMotion.usesBlurReplace(reduceMotion: false))
    }

    @Test("Reduce Motion yields no animation and no blur")
    func reduced() {
        #expect(GanchoMotion.quick(reduceMotion: true) == nil)
        #expect(GanchoMotion.smooth(reduceMotion: true) == nil)
        #expect(!GanchoMotion.usesBlurReplace(reduceMotion: true))
    }
}
