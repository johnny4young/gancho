import SwiftUI
import Testing

@testable import GanchoDesign

@Suite("Hook mark — the brand shape fits its frame")
struct HookMarkTests {
    @Test("A wide or tall frame centres the mark on the spare side")
    func centresInNonSquareFrames() {
        let square = HookMark().path(in: CGRect(x: 0, y: 0, width: 100, height: 100))
            .boundingRect
        let wide = HookMark().path(in: CGRect(x: 0, y: 0, width: 200, height: 100)).boundingRect
        let tall = HookMark().path(in: CGRect(x: 0, y: 0, width: 100, height: 300)).boundingRect
        #expect(abs(wide.midX - (square.midX + 50)) < 0.001)
        #expect(abs(wide.midY - square.midY) < 0.001)
        #expect(abs(tall.midY - (square.midY + 100)) < 0.001)
        #expect(abs(tall.width - square.width) < 0.001)
    }
}
