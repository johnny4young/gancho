import Foundation
import Testing

@testable import ClipboardCore

@Suite("SharedInbox — extension → app handoff")
struct SharedInboxTests {
    func makeInbox() -> (SharedInbox, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inbox-tests-\(UUID().uuidString)", isDirectory: true)
        return (SharedInbox(directory: dir), dir)
    }

    @Test("Deposited captures drain in order and empty the inbox")
    func depositAndDrain() throws {
        let (inbox, dir) = makeInbox()
        defer { try? FileManager.default.removeItem(at: dir) }

        try inbox.deposit(PasteboardCapture(text: "first"))
        try inbox.deposit(PasteboardCapture(text: "second"))

        let drained = try inbox.drain()
        #expect(drained.map(\.textRepresentation) == ["first", "second"])
        #expect(try inbox.drain().isEmpty)
    }

    @Test("Draining a never-used inbox returns empty, not an error")
    func drainMissingDirectory() throws {
        let (inbox, _) = makeInbox()
        #expect(try inbox.drain().isEmpty)
    }

    @Test("Image payloads survive the JSON round-trip")
    func imageRoundTrip() throws {
        let (inbox, dir) = makeInbox()
        defer { try? FileManager.default.removeItem(at: dir) }

        let capture = PasteboardCapture(
            payload: .image(data: Data([9, 9, 9]), typeIdentifier: "public.png"),
            sourceAppBundleID: "com.apple.mobilesafari")
        try inbox.deposit(capture)

        #expect(try inbox.drain() == [capture])
    }

    @Test("A poison file is discarded without wedging the inbox")
    func poisonFileDiscarded() throws {
        let (inbox, dir) = makeInbox()
        defer { try? FileManager.default.removeItem(at: dir) }

        try inbox.deposit(PasteboardCapture(text: "good"))
        try Data("not json".utf8).write(
            to: dir.appendingPathComponent("poison.json"), options: .atomic)

        let drained = try inbox.drain()
        #expect(drained.map(\.textRepresentation) == ["good"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }
}
