import Foundation
import GanchoKit
import Testing

@testable import ClipboardCore

@Suite("SharedInbox — extension → app handoff")
struct SharedInboxTests {
    func makeInbox(key: Data? = nil) -> (SharedInbox, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inbox-tests-\(UUID().uuidString)", isDirectory: true)
        return (SharedInbox(directory: dir, key: key), dir)
    }

    let key = Data(repeating: 0xC3, count: 32)

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

    @Test("An unreadable file is kept for the next drain, never destroyed")
    func unreadableFileIsDeferred() throws {
        let (inbox, dir) = makeInbox(key: key)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }

        try inbox.deposit(PasteboardCapture(text: "readable"))
        // A capture whose bytes cannot be read yet — mid-write, or briefly
        // unreadable under data protection. Simulated with permissions, which
        // is the one failure mode a test can produce deterministically.
        let unreadable = dir.appendingPathComponent("locked.json")
        try Data("{}".utf8).write(to: unreadable, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000], ofItemAtPath: unreadable.path)

        let summary = try inbox.drainReportingHealth()

        #expect(summary.captures.map(\.capture.textRepresentation) == ["readable"])
        #expect(summary.deferred == 1)
        #expect(summary.poisoned == 0)
        // The whole point: the file the drain could not read is STILL THERE.
        #expect(
            FileManager.default.fileExists(atPath: unreadable.path),
            "an unreadable capture must survive the drain that could not read it")
    }

    @Test("Bytes that were read but make no sense are counted as poison and removed")
    func poisonIsCountedAndRemoved() throws {
        let (inbox, dir) = makeInbox(key: key)
        defer { try? FileManager.default.removeItem(at: dir) }

        try inbox.deposit(PasteboardCapture(text: "good"))
        try Data("not json".utf8).write(
            to: dir.appendingPathComponent("poison.json"), options: .atomic)

        let summary = try inbox.drainReportingHealth()

        #expect(summary.captures.map(\.capture.textRepresentation) == ["good"])
        #expect(summary.poisoned == 1)
        #expect(summary.deferred == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }

    @Test("A sealed deposit read with the wrong key is poison, not a silent pass-through")
    func wrongKeyIsPoison() throws {
        let (writer, dir) = makeInbox(key: key)
        defer { try? FileManager.default.removeItem(at: dir) }
        try writer.deposit(PasteboardCapture(text: "secret"))

        let reader = SharedInbox(directory: dir, key: Data(repeating: 0x11, count: 32))
        let summary = try reader.drainReportingHealth()

        #expect(summary.captures.isEmpty)
        #expect(summary.poisoned == 1)
    }

    @Test("Prepared envelope round-trips kind; legacy files still drain")
    func preparedAndLegacy() throws {
        let (inbox, dir) = makeInbox()
        defer { try? FileManager.default.removeItem(at: dir) }

        try inbox.deposit(
            SharedInbox.PreparedCapture(
                capture: PasteboardCapture(text: "https://example.com"), kind: .url))
        // Legacy bare-capture file (pre-envelope app versions).
        try JSONEncoder().encode(PasteboardCapture(text: "legacy"))
            .write(to: dir.appendingPathComponent("legacy.json"), options: .atomic)

        let drained = try inbox.drainPrepared()
        #expect(drained.count == 2)
        #expect(drained.contains { $0.kind == .url })
        #expect(drained.contains { $0.kind == nil && $0.capture.textRepresentation == "legacy" })
    }

    @Test("Keyed deposits are sealed on disk — no plaintext JSON — and drain back")
    func sealedDepositRoundTrip() throws {
        let (inbox, dir) = makeInbox(key: key)
        defer { try? FileManager.default.removeItem(at: dir) }

        let capture = PasteboardCapture(text: "top secret content")
        try inbox.deposit(capture)

        let files = try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)
        #expect(files.count == 1)
        let raw = try Data(contentsOf: files[0])
        #expect(SealedEnvelope.isSealed(raw))
        #expect(
            !raw.contains(Data("top secret content".utf8)),
            "clipboard content must not appear as plaintext in the inbox")
        #expect(
            (try? JSONDecoder().decode(SharedInbox.PreparedCapture.self, from: raw)) == nil,
            "sealed file must not decode as plaintext JSON")

        #expect(try inbox.drain() == [capture])
        #expect(try inbox.drain().isEmpty)
    }

    @Test("A keyed inbox still drains legacy plaintext files (in-flight shares)")
    func keyedInboxDrainsLegacyPlaintext() throws {
        let (inbox, dir) = makeInbox(key: key)
        defer { try? FileManager.default.removeItem(at: dir) }
        // No deposit() runs here to create the container, so make it before
        // dropping legacy files directly — an atomic write needs its parent.
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Deposits written by a pre-sealing version: plaintext prepared
        // envelope and the even-older bare capture.
        let legacyPrepared = SharedInbox.PreparedCapture(
            capture: PasteboardCapture(text: "old"), kind: .url)
        try JSONEncoder().encode(legacyPrepared)
            .write(to: dir.appendingPathComponent("legacy-prepared.json"), options: .atomic)
        try JSONEncoder().encode(PasteboardCapture(text: "older"))
            .write(to: dir.appendingPathComponent("legacy-bare.json"), options: .atomic)

        let drained = try inbox.drainPrepared()
        #expect(drained.count == 2)
        #expect(drained.contains { $0.capture.textRepresentation == "old" && $0.kind == .url })
        #expect(drained.contains { $0.capture.textRepresentation == "older" && $0.kind == nil })
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }

    @Test("A sealed file is poison to a key-less inbox: discarded, never wedged")
    func sealedFileWithoutKeyDiscarded() throws {
        let (keyed, dir) = makeInbox(key: key)
        defer { try? FileManager.default.removeItem(at: dir) }

        try keyed.deposit(PasteboardCapture(text: "sealed"))
        let keyless = SharedInbox(directory: dir)

        #expect(try keyless.drain().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }
    @Test("A file that cannot be deleted is reported as retained, never as discarded")
    func undeletableFileIsNotReportedAsDiscarded() throws {
        let (inbox, dir) = makeInbox(key: key)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Unreadable bytes: this is the poison path, which promises deletion.
        try Data("not an envelope".utf8).write(to: dir.appendingPathComponent("wedged.json"))

        // Make the removal fail the way a real one does — the directory the
        // file lives in denies writes, so unlink cannot unlink it.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }

        let summary = try inbox.drainReportingHealth()

        // The old accounting called this poison and told the user it had been
        // discarded, while the file sat there being reprocessed on every drain.
        #expect(summary.undeletable == 1)
        #expect(summary.poisoned == 0)
        #expect(summary.captures.isEmpty)
        #expect(
            FileManager.default.fileExists(atPath: dir.appendingPathComponent("wedged.json").path),
            "the file must still be there — that is the whole point of the new count")
    }

}
