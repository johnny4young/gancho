import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

private actor SnippetBodyProbe {
    var item: ClipItem?
    var body: ClipContent?
    let gate: SearchGate?
    private(set) var contentReads = 0

    init(item: ClipItem, body: ClipContent? = .text("Hello {name}"), gate: SearchGate? = nil) {
        self.item = item
        self.body = body
        self.gate = gate
    }

    func metadata(_ id: UUID) -> ClipItem? { item?.id == id ? item : nil }
    func content(_ id: UUID) async -> ClipContent? {
        contentReads += 1
        let snapshot = body
        await gate?.hold()
        return snapshot
    }
    func replace(_ item: ClipItem?) { self.item = item }
}

@Suite("Reviewed snippet bodies", .timeLimit(.minutes(1)))
struct SnippetBodyLoaderTests {
    @Test("A current text template loads without changing its placeholders")
    func currentTemplate() async {
        let item = ClipItem(contentHash: "synthetic-template")
        let probe = SnippetBodyProbe(item: item)
        #expect(await load(item, probe: probe) == "Hello {name}")
        #expect(await probe.contentReads == 1)
    }

    @Test(
        "An edit made while the fields are being filled is rejected before reading the replacement body"
    )
    func editedBeforeInsertion() async {
        let reviewed = ClipItem(contentHash: "unchanged-deduplication-key")
        var current = reviewed
        current.updatedAt = reviewed.updatedAt.addingTimeInterval(1)
        let probe = SnippetBodyProbe(item: current)
        #expect(await load(reviewed, probe: probe) == nil)
        #expect(await probe.contentReads == 0)
    }

    @Test("A deletion during a suspended body read cannot deliver stale text")
    func deletedDuringRead() async {
        let item = ClipItem(contentHash: "synthetic-template")
        let gate = SearchGate()
        let probe = SnippetBodyProbe(item: item, gate: gate)
        let pending = Task { await load(item, probe: probe) }
        #expect(await gate.waitUntilEntered())
        await probe.replace(nil)
        await gate.release()
        #expect(await pending.value == nil)
    }

    @Test("Protected templates do not read content")
    func protectedTemplate() async {
        let item = ClipItem(kind: .secret, contentHash: "synthetic-protected", isSensitive: true)
        let probe = SnippetBodyProbe(item: item)
        #expect(await load(item, probe: probe) == nil)
        #expect(await probe.contentReads == 0)
    }

    @Test("Cancelled preparation cannot deliver a late body")
    func cancelledRead() async {
        let item = ClipItem(contentHash: "synthetic-template")
        let gate = SearchGate()
        let probe = SnippetBodyProbe(item: item, gate: gate)
        let pending = Task { await load(item, probe: probe) }
        #expect(await gate.waitUntilEntered())
        pending.cancel()
        await gate.release()
        #expect(await pending.value == nil)
    }

    private func load(_ item: ClipItem, probe: SnippetBodyProbe) async -> String? {
        await SnippetBodyLoader().load(
            item, metadata: { await probe.metadata($0) }, content: { await probe.content($0) })
    }
}
