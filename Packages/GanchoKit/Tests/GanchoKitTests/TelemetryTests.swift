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

private final class SenderFactoryProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let sender: SpySender
    private var _constructionCount = 0

    init(sender: SpySender = SpySender()) {
        self.sender = sender
    }

    var constructionCount: Int { lock.withLock { _constructionCount } }

    func makeSender() -> any TelemetrySending {
        lock.withLock { _constructionCount += 1 }
        return sender
    }
}

@Suite("Telemetry — buckets only, explicit consent first")
struct TelemetryTests {
    @Test("Events encode to names and buckets, never content")
    func encoding() {
        let (name, params) = TelemetryEvent.itemCaptured(
            type: .url, lengthBucket: .init(characterCount: 100)
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

    @Test("Fresh and disabled states never construct or call a sender")
    func disabledStates() async {
        let sender = SpySender()
        let probe = SenderFactoryProbe(sender: sender)
        let pipeline = TelemetryPipeline(
            consent: .notAsked, senderFactory: { probe.makeSender() })

        pipeline.record(.appLaunched)
        pipeline.setConsent(.disabled)
        pipeline.record(.searchPerformed)

        try? await Task.sleep(for: .milliseconds(20))
        #expect(probe.constructionCount == 0)
        #expect(sender.sent.isEmpty)
        #expect(pipeline.counts().isEmpty)
    }

    @Test("Explicit consent can count locally without a configured transport")
    func localOnly() {
        let pipeline = TelemetryPipeline(consent: .enabled)
        pipeline.record(.searchPerformed)
        pipeline.record(.searchPerformed)
        #expect(pipeline.counts() == ["search_performed": 2])
    }

    @Test("Consent constructs lazily, forwards, and withdrawal stops immediately")
    func forwards() async {
        let sender = SpySender()
        let probe = SenderFactoryProbe(sender: sender)
        let pipeline = TelemetryPipeline(
            consent: .notAsked, senderFactory: { probe.makeSender() })

        #expect(probe.constructionCount == 0)
        pipeline.setConsent(.enabled)
        #expect(probe.constructionCount == 1)
        pipeline.record(.paywallShown(trigger: .freeLimitReached))
        for _ in 0..<100 where sender.sent.isEmpty {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(sender.sent.first?.0 == "paywall_shown")
        #expect(sender.sent.first?.1 == ["trigger": "freeLimitReached"])

        pipeline.setConsent(.disabled)
        pipeline.record(.searchPerformed)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(sender.sent.count == 1)

        pipeline.setConsent(.enabled)
        #expect(probe.constructionCount == 2)
    }

    @Test("Consent persistence defaults off and preserves only explicit choices")
    func persistence() throws {
        let suite = "TelemetryTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(TelemetryConsent.load(from: defaults) == .notAsked)

        defaults.set(false, forKey: "telemetry-opted-out")
        #expect(TelemetryConsent.load(from: defaults) == .notAsked)

        defaults.set(true, forKey: "telemetry-opted-out")
        #expect(TelemetryConsent.load(from: defaults) == .disabled)

        TelemetryConsent.enabled.save(to: defaults)
        #expect(TelemetryConsent.load(from: defaults) == .enabled)
        #expect(defaults.object(forKey: "telemetry-opted-out") == nil)
    }
}
