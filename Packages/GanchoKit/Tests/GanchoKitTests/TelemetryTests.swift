import Foundation
import Testing

@testable import GanchoKit

private final class SpySender: TelemetrySending, @unchecked Sendable {
    private let lock = NSLock()
    private var _sent: [(String, [String: String])] = []
    var sent: [(String, [String: String])] { lock.withLock { _sent } }

    func send(name: String, parameters: [String: String]) async {
        lock.withLock { _sent.append((name, parameters)) }
    }
}

@Suite("Telemetry — buckets only, opt-out first")
struct TelemetryTests {
    @Test("Events encode to names and buckets, never content")
    func encoding() {
        let (name, params) = TelemetryEvent.itemCaptured(
            type: "url", lengthBucket: .init(characterCount: 100)
        ).encoded
        #expect(name == "item_captured")
        #expect(params == ["type": "url", "length_bucket": "short"])

        let (_, pasted) = TelemetryEvent.itemPastedBack(
            ageBucket: .init(age: 2 * 86_400)
        ).encoded
        #expect(pasted == ["age_bucket": "thisWeek"])
    }

    @Test("Length and age buckets cover their ranges")
    func buckets() {
        #expect(TelemetryEvent.LengthBucket(characterCount: 5) == .tiny)
        #expect(TelemetryEvent.LengthBucket(characterCount: 50_000) == .huge)
        #expect(TelemetryEvent.AgeBucket(age: 60) == .minutes)
        #expect(TelemetryEvent.AgeBucket(age: 30 * 86_400) == .older)
    }

    @Test("Opt-out swallows everything; sender receives nothing")
    func optOut() async {
        let sender = SpySender()
        let pipeline = TelemetryPipeline(sender: sender, optedOut: true)
        pipeline.record(.appLaunched)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(sender.sent.isEmpty)
        #expect(pipeline.counts().isEmpty)
    }

    @Test("Without a sender, events count locally and never leave")
    func localOnly() {
        let pipeline = TelemetryPipeline(sender: nil)
        pipeline.record(.searchPerformed)
        pipeline.record(.searchPerformed)
        #expect(pipeline.counts() == ["search_performed": 2])
    }

    @Test("With a sender, encoded events forward")
    func forwards() async {
        let sender = SpySender()
        let pipeline = TelemetryPipeline(sender: sender)
        pipeline.record(.paywallShown(trigger: "freeLimitReached"))
        for _ in 0..<100 where sender.sent.isEmpty {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(sender.sent.first?.0 == "paywall_shown")
        #expect(sender.sent.first?.1 == ["trigger": "freeLimitReached"])
    }
}
