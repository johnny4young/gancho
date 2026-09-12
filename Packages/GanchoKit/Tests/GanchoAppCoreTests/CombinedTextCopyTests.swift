import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

private struct CopyGateReader: ClipReading {
    let item = ClipItem(contentHash: "synthetic-copy")
    var text = "Synthetic text"
    var beforeContent: @Sendable () async -> Void = {}

    func items(ids: [UUID]) async throws -> [ClipItem] { ids.contains(item.id) ? [item] : [] }
    func item(id: UUID) async throws -> ClipItem? { id == item.id ? item : nil }
    func content(for id: UUID) async throws -> ClipContent? {
        await beforeContent()
        return id == item.id ? .text(text) : nil
    }
    func items(offset: Int, limit: Int) async throws -> [ClipItem] { [item] }
    func recentForBrowse(offset: Int, limit: Int) async throws -> [ClipItem] { [item] }
    func count() async throws -> Int { 1 }
    func thumbnailData(for id: UUID) async throws -> Data? { nil }
}

@MainActor private final class CombinedClipboardProbe {
    var revision = 1
    var allowed = true
    var writes: [String] = []
}

@Suite("Combined text copy boundary") @MainActor
struct CombinedTextCopyTests {
    private enum Race: Sendable { case clipboard, notAllowed, cancellation }

    @Test("A stable reviewed result writes exactly once")
    func copiesReviewedText() async throws {
        let reader = CopyGateReader()
        let probe = CombinedClipboardProbe()
        let expected = [CombinedTextPart(id: reader.item.id, content: .text(reader.text))]
        let result = try await perform(expected, reader: reader, probe: probe)
        #expect(result == .copied)
        #expect(probe.writes == [reader.text])
    }

    @Test(
        "Changes during a content read never overwrite the clipboard",
        arguments: [Race.clipboard, .notAllowed, .cancellation])
    private func preservesClipboard(_ race: Race) async throws {
        let probe = CombinedClipboardProbe()
        let reader = CopyGateReader(beforeContent: {
            switch race {
            case .clipboard: await MainActor.run { probe.revision += 1 }
            case .notAllowed: await MainActor.run { probe.allowed = false }
            case .cancellation: withUnsafeCurrentTask { $0?.cancel() }
            }
        })
        let expected = [CombinedTextPart(id: reader.item.id, content: .text(reader.text))]
        // Cancel only this child operation, never the Swift Testing task.
        let task = Task { try await perform(expected, reader: reader, probe: probe) }
        do {
            let outcome = try await task.value
            switch race {
            case .clipboard: #expect(outcome == .changed(expected))
            case .notAllowed: #expect(outcome == .blocked)
            case .cancellation: Issue.record("A canceled copy must throw cancellation")
            }
        } catch is CancellationError {
            #expect(race == .cancellation)
        }
        #expect(probe.writes.isEmpty)
    }

    @Test("Changed text must be reviewed again before copying")
    func changedContent() async throws {
        let reader = CopyGateReader(text: "Replacement")
        let probe = CombinedClipboardProbe()
        let expected = [CombinedTextPart(id: reader.item.id, content: .text("Reviewed text"))]
        let result = try await perform(expected, reader: reader, probe: probe)
        #expect(
            result == .changed([CombinedTextPart(id: reader.item.id, content: .text(reader.text))]))
        #expect(probe.writes.isEmpty)
    }

    @Test("An empty selection never clears the clipboard")
    func emptySelection() async throws {
        let probe = CombinedClipboardProbe()
        #expect(try await perform([], reader: CopyGateReader(), probe: probe) == .invalid)
        #expect(probe.writes.isEmpty)
    }

    private func perform(
        _ expected: [CombinedTextPart], reader: CopyGateReader, probe: CombinedClipboardProbe
    ) async throws -> CombinedTextCopy.Outcome {
        try await CombinedTextCopy.perform(
            expected: expected, separator: "\n\n", from: reader,
            clipboardUnchanged: { probe.revision == 1 }, isAllowed: { probe.allowed },
            write: { probe.writes.append($0) })
    }
}
