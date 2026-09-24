import Foundation
import GanchoKit
import Testing

@testable import ClipboardCore

private actor SuspendedInboxCommit {
    private var waiting: CheckedContinuation<Void, Never>?
    private var entered: CheckedContinuation<Void, Never>?
    private var didEnter = false
    func commit() async {
        didEnter = true
        entered?.resume()
        entered = nil
        await withCheckedContinuation { waiting = $0 }
    }
    func waitUntilEntered() async {
        if didEnter { return }
        await withCheckedContinuation { entered = $0 }
    }
    func release() {
        waiting?.resume()
        waiting = nil
    }
}

@Suite("Shared inbox — read commit acknowledge", .timeLimit(.minutes(1)))
struct SharedInboxDrainerTests {
    private func fixture() throws -> (SharedInbox, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "inbox-drainer-\(UUID())")
        let inbox = SharedInbox(directory: directory, key: Data(repeating: 0xC3, count: 32))
        try inbox.deposit(PasteboardCapture(text: "synthetic queued"))
        return (inbox, directory)
    }

    @Test("A refused commit remains retryable with stable identity")
    func failedCommit() async throws {
        let (inbox, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let before = try #require(inbox.readPending().deliveries.first)
        let drainer = SharedInboxDrainer()
        let failure = try await drainer.drain(inbox) { _ in throw CocoaError(.fileWriteOutOfSpace) }
        #expect(failure.failed == 1)
        #expect(failure.acknowledged == 0)
        #expect(try inbox.readPending().deliveries.first == before)
        let success = try await drainer.drain(inbox) { delivery in #expect(delivery.id == before.id)
        }
        #expect(success.acknowledged == 1)
        #expect(try inbox.readPending().deliveries.isEmpty)
    }

    @Test("Suspended commit serializes drains; cancellation leaves unacknowledged bytes")
    func reentrancyAndCancellation() async throws {
        let (inbox, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let drainer = SharedInboxDrainer()
        let gate = SuspendedInboxCommit()
        let active = Task { try await drainer.drain(inbox) { _ in await gate.commit() } }
        await gate.waitUntilEntered()
        let other = try await drainer.drain(inbox) { _ in Issue.record("reentrant commit") }
        #expect(other.isBusy)
        active.cancel()
        await gate.release()
        #expect(try await active.value.acknowledged == 0)
        #expect(try inbox.readPending().deliveries.count == 1)
        #expect(try await drainer.drain(inbox) { _ in }.acknowledged == 1)
    }

    @Test("One drain sweeps every batch and keeps a failed file for the next drain")
    func sweepsPastBatchSize() async throws {
        let (inbox, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        for index in 0..<4 { try inbox.deposit(PasteboardCapture(text: "synthetic \(index)")) }
        let failing = try #require(inbox.readPending().deliveries.first).id
        let drainer = SharedInboxDrainer(batchSize: 2)
        let report = try await drainer.drain(inbox) { delivery in
            if delivery.id == failing { throw CocoaError(.fileWriteOutOfSpace) }
        }
        #expect(report.failed == 1)
        #expect(report.acknowledged == 4)
        #expect(try inbox.readPending().deliveries.map(\.id) == [failing])
        #expect(try await drainer.drain(inbox) { _ in }.acknowledged == 1)
    }

    @Test("A drain requested mid-drain sweeps again instead of waiting for later")
    func busyRequestReruns() async throws {
        let (inbox, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let drainer = SharedInboxDrainer()
        let gate = SuspendedInboxCommit()
        let active = Task {
            try await drainer.drain(inbox) { delivery in
                if delivery.prepared.capture.textRepresentation == "synthetic queued" {
                    await gate.commit()
                }
            }
        }
        await gate.waitUntilEntered()
        try inbox.deposit(PasteboardCapture(text: "synthetic late"))
        #expect(try await drainer.drain(inbox) { _ in }.isBusy)
        await gate.release()
        #expect(try await active.value.acknowledged == 2)
        #expect(try inbox.readPending().deliveries.isEmpty)
    }

    @Test("Acknowledgement cannot remove replaced content")
    func replacedFile() throws {
        let (inbox, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let delivery = try #require(inbox.readPending().deliveries.first)
        let file = try #require(
            FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .first)
        try JSONEncoder().encode(PasteboardCapture(text: "synthetic replacement")).write(
            to: file, options: .atomic)
        #expect(throws: (any Error).self) { try inbox.acknowledge(delivery) }
        let replacement = try #require(inbox.readPending().deliveries.first)
        #expect(replacement.id != delivery.id)
        try inbox.acknowledge(replacement)
        try inbox.acknowledge(replacement)
    }

    @Test("An acknowledgement IO failure retains work after a successful commit")
    func failedAck() async throws {
        let (inbox, directory) = try fixture()
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let result = try await SharedInboxDrainer().drain(inbox) { _ in
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o500], ofItemAtPath: directory.path)
        }
        #expect(result.undeletable == 1)
        #expect(result.acknowledged == 0)
        #expect(try inbox.readPending().deliveries.count == 1)
    }
}
