import Testing

@testable import GanchoDesign

@Suite("Key caps — the Return arrow takes the system face")
struct KeyCapSymbolTests {
    @Test("Only the Return arrows take the system face")
    func returnArrowsOnly() {
        #expect("⌥↩".filter(KeyCap.usesSystemFace) == "↩")
        #expect(!"⌘K".contains(where: KeyCap.usesSystemFace))
        #expect(KeyCap.usesSystemFace("⏎"))
    }
}
