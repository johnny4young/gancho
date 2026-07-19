import Foundation
import Testing

@testable import GanchoKit

private final class SpySender: TelemetrySending, @unchecked Sendable {
    private let lock = NSLock()
    private var _sent: [(String, [String: String])] = []
    private var _shutdownCount = 0
    var sent: [(String, [String: String])] { lock.withLock { _sent } }
    var shutdownCount: Int { lock.withLock { _shutdownCount } }

    func send(name: String, parameters: [String: String]) {
        lock.withLock { _sent.append((name, parameters)) }
    }

    func shutdown() {
        lock.withLock { _shutdownCount += 1 }
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

private final class BlockingSenderFactory: @unchecked Sendable {
    let sender = SpySender()
    private let entered = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)

    func makeSender() -> any TelemetrySending {
        entered.signal()
        release.wait()
        return sender
    }

    func waitUntilEntered() -> Bool {
        // Generous timeout: the barrier is deterministic (semaphore signal),
        // so this only guards against a genuine hang. 2s was too tight for a
        // loaded CI runner where the detached task is scheduled late.
        entered.wait(timeout: .now() + 15) == .success
    }

    func unblock() {
        release.signal()
    }
}

private final class BlockingSendSender: TelemetrySending, @unchecked Sendable {
    private let lock = NSLock()
    private let entered = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)
    private var _sendCount = 0
    private var _shutdownCount = 0

    var sendCount: Int { lock.withLock { _sendCount } }
    var shutdownCount: Int { lock.withLock { _shutdownCount } }

    func send(name _: String, parameters _: [String: String]) {
        entered.signal()
        release.wait()
        lock.withLock { _sendCount += 1 }
    }

    func shutdown() {
        lock.withLock { _shutdownCount += 1 }
    }

    func waitUntilEntered() -> Bool {
        // Generous timeout: the barrier is deterministic (semaphore signal),
        // so this only guards against a genuine hang. 2s was too tight for a
        // loaded CI runner where the detached task is scheduled late.
        entered.wait(timeout: .now() + 15) == .success
    }

    func unblock() {
        release.signal()
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

        let (reuseName, reuse) = TelemetryEvent.successfulReuse(
            method: .drag, batchSize: .init(count: 4), ageBucket: .today
        ).encoded
        #expect(reuseName == "successful_reuse")
        #expect(
            reuse == ["method": "drag", "batch_size": "few", "age_bucket": "today"])

        let (milestoneName, milestone) = TelemetryEvent.activationMilestone(
            milestone: .firstSuccessfulReuse, elapsedBucket: .underMinute
        ).encoded
        #expect(milestoneName == "activation_milestone")
        #expect(
            milestone == [
                "milestone": "first_successful_reuse", "elapsed_bucket": "under_minute"
            ])
    }

    @Test("Length and age buckets cover their ranges")
    func buckets() {
        #expect(TelemetryEvent.LengthBucket(characterCount: 5) == .tiny)
        #expect(TelemetryEvent.LengthBucket(characterCount: 50_000) == .huge)
        #expect(TelemetryEvent.AgeBucket(age: 60) == .minutes)
        #expect(TelemetryEvent.AgeBucket(age: 30 * 86_400) == .older)
        #expect(TelemetryEvent.BatchSizeBucket(count: 1) == .one)
        #expect(TelemetryEvent.BatchSizeBucket(count: 5) == .few)
        #expect(TelemetryEvent.BatchSizeBucket(count: 6) == .many)
        #expect(ActivationTimeBucket(elapsed: nil) == .unknown)
        #expect(ActivationTimeBucket(elapsed: 59) == .underMinute)
        #expect(ActivationTimeBucket(elapsed: 60) == .underFiveMinutes)
        #expect(ActivationTimeBucket(elapsed: 86_400) == .later)
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
        #expect(sender.shutdownCount == 1)
        #expect(pipeline.counts().isEmpty)

        pipeline.setConsent(.enabled)
        #expect(probe.constructionCount == 2)
    }

    @Test("Withdrawal rejects and shuts down a sender still being constructed")
    func withdrawalDuringConstruction() async {
        let factory = BlockingSenderFactory()
        let pipeline = TelemetryPipeline(
            consent: .notAsked, senderFactory: { factory.makeSender() })

        let enabling = Task.detached { pipeline.setConsent(.enabled) }
        #expect(factory.waitUntilEntered())
        pipeline.setConsent(.disabled)
        factory.unblock()
        await enabling.value

        #expect(factory.sender.shutdownCount == 1)
        pipeline.record(.appLaunched)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(factory.sender.sent.isEmpty)
    }

    @Test("Withdrawal is a barrier for transport calls already in progress")
    func withdrawalWaitsForInFlightSend() async {
        let sender = BlockingSendSender()
        let pipeline = TelemetryPipeline(consent: .enabled, senderFactory: { sender })

        let recording = Task.detached { pipeline.record(.appLaunched) }
        guard sender.waitUntilEntered() else {
            sender.unblock()
            Issue.record("The test sender never received its signal")
            return
        }
        let withdrawing = Task.detached { pipeline.setConsent(.disabled) }
        try? await Task.sleep(for: .milliseconds(20))
        #expect(sender.shutdownCount == 0)

        sender.unblock()
        await recording.value
        await withdrawing.value
        #expect(sender.sendCount == 1)
        #expect(sender.shutdownCount == 1)

        pipeline.record(.searchPerformed)
        #expect(sender.sendCount == 1)
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

    @Test("Activation receipts are local, idempotent, persisted, and erasable")
    func activationReceipts() throws {
        let suite = "ActivationTrackerTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tracker = ActivationTracker(defaults: defaults)
        let start = Date(timeIntervalSince1970: 1_000)
        tracker.start(at: start)

        let capture = tracker.record(.firstCapture, at: start.addingTimeInterval(30))
        #expect(capture?.elapsedBucket == .underMinute)
        #expect(tracker.record(.firstCapture, at: start.addingTimeInterval(40)) == nil)
        _ = tracker.record(.onboardingCompleted, at: start.addingTimeInterval(45))
        _ = tracker.record(.firstSuccessfulReuse, at: start.addingTimeInterval(180))

        let restored = ActivationTracker(defaults: defaults).snapshot()
        #expect(
            restored.completedMilestones
                == [.onboardingCompleted, .firstCapture, .firstSuccessfulReuse])
        #expect(restored.timeToFirstReuse == .underFiveMinutes)
        #expect(restored.onboardingDuration == .underMinute)
        #expect(
            restored.encodedParameters[ActivationMilestone.firstCapture.rawValue] == "complete")
        #expect(
            restored.encodedParameters[ActivationMilestone.firstSearch.rawValue] == "pending")

        tracker.reset()
        #expect(tracker.snapshot().completedMilestones.isEmpty)
        #expect(tracker.snapshot().timeToFirstReuse == .unknown)
    }

    @Test("Closed telemetry schema has no arbitrary content channel")
    func closedSchemaSource() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/GanchoKit/Telemetry.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let forbiddenField = try Regex(
            #"(?i)\b(?:content\w*|query\w*|title\w*|sourceApp\w*|path\w*|hash\w*)\s*:"#)
        #expect(source.firstMatch(of: forbiddenField) == nil)

        let events: [TelemetryEvent] = [
            .appLaunched,
            .itemCaptured(type: .text, lengthBucket: .tiny),
            .itemPastedBack(ageBucket: .minutes),
            .activationMilestone(milestone: .firstSearch, elapsedBucket: .underHour),
            .activationSnapshot(
                ActivationSnapshot(
                    completedMilestones: [.firstCapture], timeToFirstReuse: .unknown,
                    onboardingDuration: .unknown)),
            .successfulReuse(method: .copy, batchSize: .one, ageBucket: .unknown),
            .itemPinned, .itemDeleted, .searchPerformed, .aiActionUsed, .syncEvent,
            .freeLimitReached, .paywallShown(trigger: .freeLimitReached),
            .upgradeStarted(plan: .lifetime), .upgradeCompleted(plan: .lifetime),
            .settingsChanged(key: .diagnostics)
        ]
        let forbiddenKeys: Set<String> = [
            "content", "query", "title", "source_app", "path", "hash"
        ]
        for event in events {
            #expect(forbiddenKeys.isDisjoint(with: event.encoded.parameters.keys))
        }
    }
}
