import CloudKit
import Foundation
import GanchoKit
import Testing

@testable import GanchoSync

@Suite("CKRecord mapping — schema, encryption, assets, conflict")
struct ClipRecordMapperTests {
    private let zoneID = CKRecordZone.ID(
        zoneName: ClipRecordMapper.zoneName, ownerName: CKCurrentUserDefaultName)

    private let png = Data(
        base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
    )!

    @Test("Text clip round-trips through a record")
    func textRoundTrip() throws {
        let item = ClipItem(
            kind: .url, title: "Example", preview: "https://example.com",
            contentHash: "h1", sourceAppBundleID: "com.apple.Safari", tags: ["web"])
        let record = try #require(
            ClipRecordMapper.record(
                for: item, content: .text("https://example.com/full"), systemFields: nil,
                zoneID: zoneID))
        let decoded = try #require(ClipRecordMapper.decode(record))

        #expect(decoded.item.id == item.id)
        #expect(decoded.item.kind == .url)
        #expect(decoded.item.title == "Example")
        #expect(decoded.item.contentHash == "h1")
        #expect(decoded.item.tags == ["web"])
        #expect(decoded.content == .text("https://example.com/full"))
        #expect(record.recordType == ClipRecordMapper.recordType)
        #expect(record.recordID.recordName == item.id.uuidString)
    }

    @Test("A clip's board membership rides its record")
    func clipBoardMembershipRoundTrips() throws {
        let item = ClipItem(preview: "in two boards", contentHash: "h")
        let a = UUID()
        let b = UUID()
        let record = try #require(
            ClipRecordMapper.record(
                for: item, content: .text("x"), systemFields: nil, zoneID: zoneID,
                boardIDs: [a, b]))
        #expect(Set(ClipRecordMapper.boardIDs(from: record)) == Set([a, b]))
        // Absent field decodes to an empty set, not a crash.
        let bare = try #require(
            ClipRecordMapper.record(
                for: item, content: .text("x"), systemFields: nil, zoneID: zoneID))
        #expect(ClipRecordMapper.boardIDs(from: bare).isEmpty)
    }

    @Test("A board round-trips through its record")
    func boardRoundTrips() throws {
        let boardsZone = CKRecordZone.ID(
            zoneName: BoardRecordMapper.zoneName, ownerName: CKCurrentUserDefaultName)
        let board = Pinboard(name: "Work", sfSymbol: "briefcase", sortIndex: 3)
        let record = try #require(
            BoardRecordMapper.record(for: board, systemFields: nil, zoneID: boardsZone))
        let decoded = try #require(BoardRecordMapper.decode(record))
        #expect(decoded.id == board.id)
        #expect(decoded.name == "Work")
        #expect(decoded.sfSymbol == "briefcase")
        #expect(decoded.sortIndex == 3)
        #expect(decoded.isSystem == false)
        #expect(record.recordType == BoardRecordMapper.recordType)
    }

    @Test("Content and preview live in encryptedValues, never plain fields")
    func contentIsEncrypted() throws {
        let item = ClipItem(preview: "secret preview", contentHash: "h")
        let record = try #require(
            ClipRecordMapper.record(
                for: item, content: .text("the secret body"), systemFields: nil, zoneID: zoneID))

        // Plain accessor must NOT expose content/preview…
        #expect(record["contentText"] == nil)
        #expect(record["preview"] == nil)
        // …it lives in the encrypted bag.
        #expect(record.encryptedValues["contentText"] as? String == "the secret body")
        #expect(record.encryptedValues["preview"] as? String == "secret preview")
        // Metadata stays plain (needed for conflict/ordering).
        #expect(record["kind"] as? String == "text")
    }

    @Test("Image clip rides a CKAsset and round-trips")
    func imageRoundTrip() throws {
        let item = ClipItem(kind: .image, preview: "Image", contentHash: "h2")
        let record = try #require(
            ClipRecordMapper.record(
                for: item, content: .binary(data: png, typeIdentifier: "public.png"),
                systemFields: nil, zoneID: zoneID))
        #expect(record["contentAsset"] is CKAsset)
        let decoded = try #require(ClipRecordMapper.decode(record))
        #expect(decoded.content == .binary(data: png, typeIdentifier: "public.png"))
    }

    @Test("Binary over the size limit syncs metadata but skips the asset")
    func oversizeBinarySkipsAsset() throws {
        let item = ClipItem(kind: .image, preview: "Big", contentHash: "h3")
        let record = try #require(
            ClipRecordMapper.record(
                for: item, content: .binary(data: png, typeIdentifier: "public.png"),
                systemFields: nil, zoneID: zoneID, maxAssetBytes: 1))
        #expect(record["contentAsset"] == nil, "asset skipped over the limit")
        let decoded = try #require(ClipRecordMapper.decode(record))
        #expect(decoded.item.kind == .image)
        #expect(decoded.content == nil, "no asset, no content — metadata only")
    }

    @Test("System fields archive and restore the record identity")
    func systemFieldsRoundTrip() throws {
        let item = ClipItem(preview: "x", contentHash: "h")
        let first = try #require(
            ClipRecordMapper.record(
                for: item, content: .text("x"), systemFields: nil, zoneID: zoneID)
        )
        let archived = ClipRecordMapper.encodeSystemFields(first)
        // Rebuild from the archived fields — same record identity preserved.
        let rebuilt = try #require(
            ClipRecordMapper.record(
                for: item, content: .text("x"), systemFields: archived, zoneID: zoneID))
        #expect(rebuilt.recordID == first.recordID)
    }

    @Test("Binary assets stage in the dedicated subdir and are removed on sent")
    func assetStagingLifecycle() throws {
        let item = ClipItem(kind: .image, preview: "Image", contentHash: "h5")
        let record = try #require(
            ClipRecordMapper.record(
                for: item, content: .binary(data: png, typeIdentifier: "public.png"),
                systemFields: nil, zoneID: zoneID))
        let asset = try #require(record["contentAsset"] as? CKAsset)
        let url = try #require(asset.fileURL)
        #expect(
            url.deletingLastPathComponent().resolvingSymlinksInPath().path
                == ClipRecordMapper.assetStagingDirectory.resolvingSymlinksInPath().path,
            "plaintext bytes stage only in the dedicated directory")
        #expect(FileManager.default.fileExists(atPath: url.path))

        // The sent-record hook deletes exactly this record's staged file.
        ClipRecordMapper.removeStagedAsset(for: record)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("The staging sweep reaps stale files and spares fresh ones")
    func stagedAssetSweep() throws {
        let directory = ClipRecordMapper.assetStagingDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stale = directory.appendingPathComponent("gancho-asset-\(UUID().uuidString)")
        let fresh = directory.appendingPathComponent("gancho-asset-\(UUID().uuidString)")
        try png.write(to: stale)
        try png.write(to: fresh)
        defer { try? FileManager.default.removeItem(at: fresh) }
        // Backdate the stale file past the sweep age, as a crashed send would.
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -7200)], ofItemAtPath: stale.path)

        ClipRecordMapper.sweepStagedAssets(olderThan: 3600)

        #expect(!FileManager.default.fileExists(atPath: stale.path), "the orphan is reaped")
        #expect(FileManager.default.fileExists(atPath: fresh.path), "an in-flight file survives")
    }

    @Test("removeStagedAsset never touches a file outside the staging directory")
    func removeStagedAssetIgnoresForeignFiles() throws {
        let foreign = FileManager.default.temporaryDirectory
            .appendingPathComponent("gancho-foreign-\(UUID().uuidString)")
        try png.write(to: foreign)
        defer { try? FileManager.default.removeItem(at: foreign) }
        let item = ClipItem(kind: .image, preview: "Image", contentHash: "h6")
        let record = try #require(
            ClipRecordMapper.record(for: item, content: nil, systemFields: nil, zoneID: zoneID))
        // A fetched record's asset lives in CloudKit-managed storage, not ours.
        record["contentAsset"] = CKAsset(fileURL: foreign)

        ClipRecordMapper.removeStagedAsset(for: record)

        #expect(FileManager.default.fileExists(atPath: foreign.path))
    }

    @Test("Last-writer-wins by updatedAt")
    func conflictRule() {
        let now = Date(timeIntervalSince1970: 1_000)
        let older = now.addingTimeInterval(-10)
        let newer = now.addingTimeInterval(10)
        #expect(ClipRecordMapper.remoteWins(localUpdatedAt: nil, remoteUpdatedAt: now))
        #expect(ClipRecordMapper.remoteWins(localUpdatedAt: older, remoteUpdatedAt: newer))
        #expect(!ClipRecordMapper.remoteWins(localUpdatedAt: newer, remoteUpdatedAt: older))
        #expect(ClipRecordMapper.remoteWins(localUpdatedAt: now, remoteUpdatedAt: now))
    }
}
