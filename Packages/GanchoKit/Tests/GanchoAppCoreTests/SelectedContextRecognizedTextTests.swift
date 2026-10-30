import Foundation
import GRDB
@_spi(GanchoInternal) import GanchoKit
import Testing

@testable import GanchoAppCore

@Suite("Selected context — recognized text from images")
@MainActor
struct SelectedContextRecognizedTextTests {
    private static let reviewedText = "Queue sits between API and workers"

    private struct Fixture {
        let store: GRDBClipboardStore
        let image: UUID
        let note: UUID
        var ids: [UUID] { [note, image] }
    }

    private func makeFixture(imageText: String? = reviewedText) async throws -> Fixture {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory.appendingPathComponent(
                    "selected-recognized-\(UUID())")))
        try store.migrate()
        let image = ClipItem(kind: .image, title: "Diagram", contentHash: "selected-image")
        try await store.insert(
            image, content: .binary(data: Data([0x89, 0x50]), typeIdentifier: "public.png"))
        if let imageText { try await store.attachExtractedText(id: image.id, text: imageText) }
        let note = ClipItem(preview: "Deploy note", contentHash: "selected-note")
        try await store.insert(note, content: .text("Deploy note"))
        return Fixture(store: store, image: image.id, note: note.id)
    }

    private func load(
        _ fixture: Fixture, offeringText: Bool = true
    ) async throws
        -> [CombinedTextPart]
    {
        try await CombinedTextService().load(
            ids: fixture.ids, from: fixture.store,
            recognizedText: offeringText ? fixture.store : nil)
    }

    @Test("An image offers its stored text only when the caller asks for it")
    func loadOffersRecognizedTextOnRequest() async throws {
        let fixture = try await makeFixture()
        #expect(
            try await load(fixture).map(\.content) == [
                .text("Deploy note"), .recognizedText(Self.reviewedText)
            ])
        #expect(
            try await load(fixture, offeringText: false).map(\.content) == [
                .text("Deploy note"), .incompatible
            ])
    }

    @Test("An image without stored text stays incompatible")
    func imageWithoutTextIsIncompatible() async throws {
        let fixture = try await makeFixture(imageText: nil)
        #expect(try await load(fixture).last?.content == .incompatible)
    }

    @Test("Recognized text that reads as a secret is protected, not offered")
    func secretTextIsProtected() async throws {
        let fixture = try await makeFixture(
            imageText: "export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE")
        #expect(try await load(fixture).last?.content == .protected)
    }

    @Test("Recognized text over the byte limit is too large; text at the limit is offered")
    func oversizedTextIsTooLarge() {
        let limit = CombinedTextService.maximumUTF8Bytes
        let atLimit = String(repeating: "a", count: limit)
        #expect(CombinedTextService.recognizedContent(atLimit) == .recognizedText(atLimit))
        #expect(CombinedTextService.recognizedContent(atLimit + "a") == .tooLarge)
    }

    @Test("Combined copy never joins recognized text")
    func combinedCopyRejectsRecognizedText() throws {
        let part = CombinedTextPart(id: UUID(), content: .recognizedText("text"))
        #expect(try CombinedTextService().compose([part], separator: "\n") == nil)
    }

    @Test("Recognized text the user has not approved blocks formatting")
    func unapprovedTextIsIncompatible() throws {
        let part = CombinedTextPart(id: UUID(), content: .recognizedText(Self.reviewedText))
        #expect(throws: SelectedContextError.incompatibleSelection) {
            try SelectedContextFormatter.format([part])
        }
    }

    @Test("Approved text is labelled in Markdown and bound to its exact digest")
    func approvedTextIsLabelledAndBound() throws {
        let note = CombinedTextPart(id: UUID(), content: .text("Deploy note"))
        let image = CombinedTextPart(id: UUID(), content: .recognizedText(Self.reviewedText))
        let prepared = try SelectedContextFormatter.format(
            [note, image], approvedRecognizedText: [image.id])

        #expect(prepared.markdown.contains("## Clip 1\n"))
        #expect(
            prepared.markdown.contains(
                "## Clip 2 (text recognized from an image)\n\n```text\n\(Self.reviewedText)\n```"))
        #expect(prepared.representations.keys.sorted() == [image.id])
        #expect(
            prepared.representations[image.id]?.authorizes(recognizedText: Self.reviewedText)
                == true)
    }

    @Test("The grant carries representations only for approved images")
    func grantCarriesRepresentations() throws {
        let note = CombinedTextPart(id: UUID(), content: .text("Deploy note"))
        let image = CombinedTextPart(id: UUID(), content: .recognizedText(Self.reviewedText))
        let mixed = try SelectedContextDelivery.grant(
            for: SelectedContextFormatter.format([note, image], approvedRecognizedText: [image.id]),
            clientName: "Client")
        let textOnly = try SelectedContextDelivery.grant(
            for: SelectedContextFormatter.format([note]), clientName: "Client")

        let pack = try #require(mixed.contextPack)
        #expect(pack.representation(of: image.id).authorizes(recognizedText: Self.reviewedText))
        #expect(pack.representation(of: note.id) == .original)
        #expect(textOnly.contextPack?.clipRepresentations == nil)
    }

    @Test("Delivery binds the reviewed digest and the reviewed revisions")
    func deliveryBindsReviewedText() async throws {
        let fixture = try await makeFixture()
        let reviewed = try await load(fixture)
        var delivered: PreparedSelectedContext?
        let outcome = try await SelectedContextDelivery.perform(
            expected: reviewed, approvedRecognizedText: [fixture.image], from: fixture.store,
            recognizedText: fixture.store, isAllowed: { true }, destinationUnchanged: { true },
            deliver: { delivered = $0 })

        #expect(outcome == .delivered)
        let prepared = try #require(delivered)
        #expect(Set(prepared.revisions.keys) == Set(fixture.ids))
        #expect(
            prepared.representations[fixture.image]?.authorizes(recognizedText: Self.reviewedText)
                == true)
    }

    @Test("Text re-recognized after review stops delivery and must be approved again")
    func rewrittenTextNeedsNewApproval() async throws {
        let fixture = try await makeFixture()
        let reviewed = try await load(fixture)
        try await fixture.store.attachExtractedText(id: fixture.image, text: "Unreviewed text")
        var deliveries = 0
        let outcome = try await SelectedContextDelivery.perform(
            expected: reviewed, approvedRecognizedText: [fixture.image], from: fixture.store,
            recognizedText: fixture.store, isAllowed: { true }, destinationUnchanged: { true },
            deliver: { _ in deliveries += 1 })

        guard case .changed(let current) = outcome else {
            Issue.record("expected a changed outcome, got \(outcome)")
            return
        }
        #expect(deliveries == 0)
        #expect(current.last?.content == .recognizedText("Unreviewed text"))
        #expect(
            SelectedContextDelivery.retainedApprovals(
                [fixture.image], reviewed: reviewed, current: current
            ).isEmpty)
    }

    @Test("Approvals survive a reload only for unchanged recognized text")
    func retainedApprovals() {
        let kept = UUID()
        let changed = UUID()
        let note = UUID()
        let reviewed = [
            CombinedTextPart(id: kept, content: .recognizedText("same")),
            CombinedTextPart(id: changed, content: .recognizedText("before")),
            CombinedTextPart(id: note, content: .text("note"))
        ]
        let current = [
            CombinedTextPart(id: kept, content: .recognizedText("same")),
            CombinedTextPart(id: changed, content: .recognizedText("after")),
            CombinedTextPart(id: note, content: .text("note"))
        ]
        #expect(
            SelectedContextDelivery.retainedApprovals(
                [kept, changed, note], reviewed: reviewed, current: current) == [kept])
    }
}
