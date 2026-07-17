import Foundation
import Testing

@testable import GanchoAppCore

/// In-memory HintStore — proves the once-ever rule without real defaults.
private final class FakeHintStore: HintStore, @unchecked Sendable {
    private var bools: [String: Bool] = [:]
    private var ints: [String: Int] = [:]
    func bool(forKey key: String) -> Bool { bools[key] ?? false }
    func set(_ value: Bool, forKey key: String) { bools[key] = value }
    func integer(forKey key: String) -> Int { ints[key] ?? 0 }
    func set(_ value: Int, forKey key: String) { ints[key] = value }
}

@Suite("One-shot hints — content-free, fires exactly once")
struct OneShotHintsTests {
    @Test("A threshold-3 hint fires on the third trigger, then never again")
    func firesAtThresholdOnce() {
        let hints = OneShotHints(store: FakeHintStore())
        #expect(hints.noteTrigger(.quickPasteNumbers) == nil)  // 1
        #expect(hints.noteTrigger(.quickPasteNumbers) == nil)  // 2
        #expect(hints.noteTrigger(.quickPasteNumbers) == .quickPasteNumbers)  // 3 → fires
        #expect(hints.noteTrigger(.quickPasteNumbers) == nil)  // never again
        #expect(hints.hasFired(.quickPasteNumbers))
    }

    @Test("A threshold-1 hint fires on first sight")
    func firesImmediatelyWhenThresholdIsOne() {
        let hints = OneShotHints(store: FakeHintStore())
        #expect(hints.noteTrigger(.fullPreviewCommandY) == .fullPreviewCommandY)
        #expect(hints.noteTrigger(.fullPreviewCommandY) == nil)
    }

    @Test("Hints are independent — one firing doesn't affect another")
    func hintsAreIndependent() {
        let hints = OneShotHints(store: FakeHintStore())
        _ = hints.noteTrigger(.fullPreviewCommandY)  // fires
        #expect(hints.hasFired(.fullPreviewCommandY))
        #expect(!hints.hasFired(.fileWithCommandB))
        #expect(hints.noteTrigger(.fileWithCommandB) == nil)  // still counting
    }

    @Test("Suppressing a hint stops it from ever firing")
    func suppressPreemptsTheTrigger() {
        let hints = OneShotHints(store: FakeHintStore())
        hints.suppress(.quickPasteNumbers)
        #expect(hints.hasFired(.quickPasteNumbers))
        #expect(hints.noteTrigger(.quickPasteNumbers) == nil)
        #expect(hints.noteTrigger(.quickPasteNumbers) == nil)
        #expect(hints.noteTrigger(.quickPasteNumbers) == nil)
    }

    @Test("State survives across model instances backed by the same store")
    func persistsAcrossInstances() {
        let store = FakeHintStore()
        _ = OneShotHints(store: store).noteTrigger(.fullPreviewCommandY)  // fires
        // A fresh model over the same store must see it as already fired.
        #expect(OneShotHints(store: store).hasFired(.fullPreviewCommandY))
        #expect(OneShotHints(store: store).noteTrigger(.fullPreviewCommandY) == nil)
    }

    @Test("Every hint key is stable and unique (content-free persistence)")
    func hintKeysAreStableAndUnique() {
        let keys = Hint.allCases.map(\.rawValue)
        #expect(Set(keys).count == keys.count)
        #expect(keys.allSatisfy { $0.hasPrefix("hint.") })
    }
}
