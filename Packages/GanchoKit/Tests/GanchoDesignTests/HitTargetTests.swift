import Testing

@testable import GanchoDesign

@Suite("Hit targets — touch 44, Mac controls 28, rows 24")
struct HitTargetTests {
    @Test func targetsFollowTheVocabulary() {
        #expect(GanchoTokens.HitTarget.touch == 44)
        #expect(GanchoTokens.HitTarget.control == 28)
        #expect(GanchoTokens.HitTarget.row == 24)
    }

    @Test func buttonsUseThePlatformTarget() {
        #if os(iOS)
            #expect(GanchoTokens.HitTarget.button == GanchoTokens.HitTarget.touch)
        #else
            #expect(GanchoTokens.HitTarget.button == GanchoTokens.HitTarget.control)
        #endif
    }
}
