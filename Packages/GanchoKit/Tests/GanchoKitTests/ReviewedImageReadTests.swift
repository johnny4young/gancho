import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Reviewed images — storage, sweep and MCP reads")
struct ReviewedImageReadTests {
    private static let recognizedText = "Queue sits between API and workers"

    private struct Fixture {
        let store: GRDBClipboardStore
        let blobs: BlobStore
        let image: ClipItem
        let note: ClipItem
        let derivative: ReviewedImageDerivative
    }

    private func makeFixture() async throws -> Fixture {
        let blobs = BlobStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(
                "reviewed-image-\(UUID())"))
        let store = GRDBClipboardStore(writer: try DatabaseQueue(), blobs: blobs)
        try store.migrate()
        let source = ReviewedImageFixture.encode(
            ReviewedImageFixture.image(width: 320, height: 120))
        let image = ClipItem(
            updatedAt: Date.now.addingTimeInterval(-60), kind: .image, title: "Diagram",
            contentHash: "reviewed-source")
        try await store.insert(image, content: .binary(data: source, typeIdentifier: "public.png"))
        try await store.attachExtractedText(id: image.id, text: Self.recognizedText)
        let note = ClipItem(
            updatedAt: Date.now.addingTimeInterval(-60), preview: "Deploy note",
            contentHash: "reviewed-note")
        try await store.insert(note, content: .text("Deploy note"))
        return Fixture(
            store: store, blobs: blobs, image: image, note: note,
            derivative: try ReviewedImageDerivative.make(from: source))
    }

    private func grant(
        _ fixture: Fixture, _ shares: [UUID: [MCPClipRepresentation]],
        expiresAt: Date? = nil
    ) -> MCPClientGrant {
        let items = [fixture.image, fixture.note]
        return MCPClientGrant(
            clientName: "Reviewed image fixture", scope: .all,
            contextPack: MCPContextPack(
                name: "Reviewed", clipIDs: Set(items.map(\.id)),
                clipRevisions: Dictionary(
                    uniqueKeysWithValues: items.map { ($0.id.uuidString, $0.contextRevision) }),
                clipRepresentations: Dictionary(
                    uniqueKeysWithValues: shares.map { ($0.key.uuidString, $0.value) })),
            expiresAt: expiresAt)
    }

    private func read(
        _ id: UUID, _ grant: MCPClientGrant, in fixture: Fixture
    ) async throws
        -> MCPClipReadResult
    {
        try await fixture.store.readForMCP(
            id: id, grant: grant, requiresContextPack: true, now: .now)
    }

    private struct Reviewed: Equatable {
        let id: UUID
        let text: String?
        let image: Data?
    }

    private func reviewed(_ result: MCPClipReadResult) -> Reviewed? {
        guard case .reviewed(let item, let text, let image) = result else { return nil }
        return Reviewed(id: item.id, text: text, image: image)
    }

    private func imageShare(_ fixture: Fixture) -> MCPClipRepresentation {
        .reviewedImage(MCPReviewedImage(fixture.derivative))
    }

    @Test("An image share returns the stored derivative's exact bytes and no text")
    func returnsStoredDerivative() async throws {
        let fixture = try await makeFixture()
        try fixture.store.saveReviewedImage(fixture.derivative)
        let result = try await read(
            fixture.image.id, grant(fixture, [fixture.image.id: [imageShare(fixture)]]),
            in: fixture)
        #expect(
            reviewed(result)
                == Reviewed(id: fixture.image.id, text: nil, image: fixture.derivative.data))
    }

    @Test("Text and image shares are returned together when both were reviewed")
    func returnsBothShares() async throws {
        let fixture = try await makeFixture()
        try fixture.store.saveReviewedImage(fixture.derivative)
        let shares: [MCPClipRepresentation] = [
            .recognizedText(reviewing: Self.recognizedText), imageShare(fixture)
        ]
        let result = try await read(
            fixture.image.id, grant(fixture, [fixture.image.id: shares]), in: fixture)
        #expect(
            reviewed(result)
                == Reviewed(
                    id: fixture.image.id, text: Self.recognizedText,
                    image: fixture.derivative.data))
    }

    @Test("A missing derivative is withheld, never replaced by the original image")
    func missingDerivativeIsWithheld() async throws {
        let fixture = try await makeFixture()
        let result = try await read(
            fixture.image.id, grant(fixture, [fixture.image.id: [imageShare(fixture)]]),
            in: fixture)
        #expect(reviewed(result) == Reviewed(id: fixture.image.id, text: nil, image: nil))
    }

    @Test("A derivative file whose bytes changed is withheld")
    func tamperedDerivativeIsWithheld() async throws {
        let fixture = try await makeFixture()
        let directory = fixture.blobs.reviewedImages.directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("substituted bytes".utf8).write(
            to: directory.appendingPathComponent(fixture.derivative.sha256))
        let result = try await read(
            fixture.image.id, grant(fixture, [fixture.image.id: [imageShare(fixture)]]),
            in: fixture)
        #expect(reviewed(result) == Reviewed(id: fixture.image.id, text: nil, image: nil))
    }

    @Test("An image share on a clip that is not an image is outside the context")
    func textClipCannotShareAnImage() async throws {
        let fixture = try await makeFixture()
        try fixture.store.saveReviewedImage(fixture.derivative)
        let result = try await read(
            fixture.note.id, grant(fixture, [fixture.note.id: [imageShare(fixture)]]),
            in: fixture)
        #expect(result == .outsideContext)
    }

    @Test("The sweep keeps derivatives a live grant references and deletes the rest")
    func sweepKeepsReferencedDerivatives() async throws {
        let fixture = try await makeFixture()
        let other = try ReviewedImageDerivative.make(
            from: ReviewedImageFixture.encode(ReviewedImageFixture.image(width: 64, height: 64)))
        try fixture.store.saveReviewedImage(fixture.derivative)
        try fixture.store.saveReviewedImage(other)

        #expect(fixture.store.removeReviewedImages(except: [fixture.derivative.sha256]) == 1)
        #expect(try fixture.blobs.reviewedImages.read(hash: fixture.derivative.sha256) != nil)
        #expect(try fixture.blobs.reviewedImages.read(hash: other.sha256) == nil)
    }

    @Test("The clip orphan sweep never deletes the reviewed-image directory")
    func orphanSweepSparesDerivatives() async throws {
        let fixture = try await makeFixture()
        try fixture.store.saveReviewedImage(fixture.derivative)
        _ = try await fixture.store.removeOrphanedBlobs()
        #expect(try fixture.blobs.reviewedImages.read(hash: fixture.derivative.sha256) != nil)
    }

    @Test("Only active grants keep their reviewed images live")
    func liveReviewedImages() async throws {
        let fixture = try await makeFixture()
        let share = [fixture.image.id: [imageShare(fixture)]]
        var revoked = grant(fixture, share)
        revoked.revokedAt = .now
        var config = MCPServerConfig()
        config.grants = [grant(fixture, share, expiresAt: .now.addingTimeInterval(-1)), revoked]
        #expect(config.liveReviewedImages().isEmpty)
        config.grants.append(grant(fixture, share, expiresAt: .now.addingTimeInterval(3_600)))
        #expect(config.liveReviewedImages() == [fixture.derivative.sha256])
    }
}
