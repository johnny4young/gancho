import CoreGraphics
import Testing

@testable import GanchoAppCore

@Suite("Screen OCR region geometry")
struct ScreenTextRegionTests {
    @Test("Region uses logical points, never Retina pixel multiplication")
    func points() {
        let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let result = ScreenTextRegion.selection(
            from: CGPoint(x: 100, y: 800), to: CGPoint(x: 400, y: 600), display: display,
            primaryDisplayTop: 900)
        #expect(result == CGRect(x: 100, y: 100, width: 300, height: 200))
    }

    @Test("Negative display coordinates and reversed drag are preserved")
    func secondaryDisplay() {
        let display = CGRect(x: -1920, y: -100, width: 1920, height: 1080)
        let result = ScreenTextRegion.selection(
            from: CGPoint(x: -100, y: 400), to: CGPoint(x: -500, y: 100), display: display,
            primaryDisplayTop: 900)
        #expect(result == CGRect(x: -500, y: 500, width: 400, height: 300))
    }

    @Test("Drag cannot leave its starting display; clicks and tiny regions cancel")
    func confinementAndCancel() {
        let display = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(
            ScreenTextRegion.selection(
                from: CGPoint(x: 90, y: 90), to: CGPoint(x: 200, y: 200), display: display,
                primaryDisplayTop: 100) == CGRect(x: 90, y: 0, width: 10, height: 10))
        #expect(
            ScreenTextRegion.selection(
                from: .zero, to: CGPoint(x: 1, y: 1), display: display, primaryDisplayTop: 100)
                == nil)
        #expect(
            ScreenTextRegion.selection(
                from: .zero, to: .zero, display: display, primaryDisplayTop: 100) == nil)
    }
}
