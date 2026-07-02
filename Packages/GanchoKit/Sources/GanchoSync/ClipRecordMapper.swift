import CloudKit
import Foundation
import GanchoKit

/// Translates between `ClipItem` (+ content) and `CKRecord`. This is the
/// only file that knows CloudKit's record shape — get it right ONCE, because
/// promoting the schema to the CloudKit production environment is one-way.
///
/// Privacy: everything that can carry clipboard content — `contentText`,
/// `preview`, `title` — goes in `encryptedValues` (end-to-end encrypted in
/// the private database). Binary payloads ride a `CKAsset` (encrypted at
/// rest by CloudKit) with a configurable size ceiling. Metadata needed for
/// ordering/conflict (kind, hashes, timestamps, flags) stays in plain
/// fields — it is not content.
public enum ClipRecordMapper {
    public static let recordType = "Clip"
    public static let zoneName = "ClipsZone"
    /// Skip syncing binary payloads larger than this (metadata still syncs).
    public static let defaultMaxAssetBytes = 50 * 1024 * 1024

    /// Builds (or updates) the CKRecord for a clip. Pass the archived system
    /// fields to preserve the record's change tag on update; nil mints a new
    /// record. Returns nil only if the system fields fail to unarchive.
    public static func record(
        for item: ClipItem,
        content: ClipContent?,
        systemFields: Data?,
        zoneID: CKRecordZone.ID,
        maxAssetBytes: Int = defaultMaxAssetBytes,
        boardIDs: [UUID] = []
    ) -> CKRecord? {
        let record: CKRecord
        if let systemFields {
            guard let unarchived = decodeSystemFields(systemFields) else { return nil }
            record = unarchived
        } else {
            let id = CKRecord.ID(recordName: item.id.uuidString, zoneID: zoneID)
            record = CKRecord(recordType: recordType, recordID: id)
        }

        // Plain metadata (ordering, conflict, structure — not content).
        record["kind"] = item.kind.rawValue
        record["contentHash"] = item.contentHash
        record["createdAt"] = item.createdAt
        record["updatedAt"] = item.updatedAt
        record["lastUsedAt"] = item.lastUsedAt
        record["expiresAt"] = item.expiresAt
        record["sourceAppBundleID"] = item.sourceAppBundleID
        record["sourceDeviceName"] = item.sourceDeviceName
        record["isPinned"] = item.isPinned ? 1 : 0
        record["isSensitive"] = item.isSensitive ? 1 : 0
        record["tags"] =
            (try? String(data: JSONEncoder().encode(item.tags), encoding: .utf8))
            ?? "[]"
        // Board membership is structural (which collections a clip is in), not
        // content — so it rides a plain field. Board names sync separately.
        record["boardIDs"] = boardIDs.map(\.uuidString)

        // Content + anything derived from it → encrypted.
        record.encryptedValues["title"] = item.title
        record.encryptedValues["preview"] = item.preview

        switch content {
        case .text(let text):
            record.encryptedValues["contentText"] = text
            record["contentTypeIdentifier"] = nil
        case .fileReferences(let paths):
            record.encryptedValues["contentText"] = paths.joined(separator: "\n")
            record["contentTypeIdentifier"] = "public.file-url"
        case .binary(let data, let typeIdentifier):
            record["contentTypeIdentifier"] = typeIdentifier
            if data.count <= maxAssetBytes, let asset = makeAsset(data) {
                record["contentAsset"] = asset
            }
        case nil:
            break
        }
        return record
    }

    /// Decodes a fetched record into a clip + its content. Returns nil for a
    /// record whose name is not a clip UUID.
    public static func decode(_ record: CKRecord) -> (item: ClipItem, content: ClipContent?)? {
        guard let id = UUID(uuidString: record.recordID.recordName) else { return nil }

        let item = ClipItem(
            id: id,
            createdAt: record["createdAt"] as? Date ?? .now,
            updatedAt: record["updatedAt"] as? Date ?? .now,
            lastUsedAt: record["lastUsedAt"] as? Date,
            kind: ClipContentKind(rawValue: record["kind"] as? String ?? "") ?? .text,
            title: record.encryptedValues["title"] as? String ?? "",
            preview: record.encryptedValues["preview"] as? String ?? "",
            contentHash: record["contentHash"] as? String ?? "",
            sourceAppBundleID: record["sourceAppBundleID"] as? String,
            sourceDeviceName: record["sourceDeviceName"] as? String,
            isPinned: (record["isPinned"] as? Int ?? 0) == 1,
            isSensitive: (record["isSensitive"] as? Int ?? 0) == 1,
            expiresAt: record["expiresAt"] as? Date,
            tags: decodeTags(record["tags"] as? String))

        let content: ClipContent?
        if let asset = record["contentAsset"] as? CKAsset, let url = asset.fileURL,
            let data = try? Data(contentsOf: url)
        {
            content = .binary(
                data: data,
                typeIdentifier: record["contentTypeIdentifier"] as? String ?? "public.data")
        } else if record["contentTypeIdentifier"] as? String == "public.file-url",
            let joined = record.encryptedValues["contentText"] as? String
        {
            content = .fileReferences(joined.split(separator: "\n").map(String.init))
        } else if let text = record.encryptedValues["contentText"] as? String {
            content = .text(text)
        } else {
            content = nil
        }
        return (item, content)
    }

    /// The board ids a synced clip belongs to. Membership rides the clip
    /// record; board metadata (name, glyph) syncs separately as a `Board`
    /// record, so an unknown id here resolves to a placeholder until that
    /// arrives.
    public static func boardIDs(from record: CKRecord) -> [UUID] {
        (record["boardIDs"] as? [String])?.compactMap { UUID(uuidString: $0) } ?? []
    }

    /// Last-writer-wins by `updatedAt`: apply the remote only if it is at
    /// least as new as the local copy. Pure, so it is unit-tested directly.
    public static func remoteWins(localUpdatedAt: Date?, remoteUpdatedAt: Date) -> Bool {
        guard let localUpdatedAt else { return true }
        return remoteUpdatedAt >= localUpdatedAt
    }

    /// Archives a record's system fields (change tag etc.) for persistence.
    public static func encodeSystemFields(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        return coder.encodedData
    }

    private static func decodeSystemFields(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        let record = CKRecord(coder: coder)
        coder.finishDecoding()
        return record
    }

    // MARK: - CKAsset staging
    //
    // A CKAsset's payload must live in a file CloudKit reads later, at batch
    // send time — so `makeAsset` cannot delete it, and CloudKit never deletes
    // the caller's source file either. Left alone, every synced binary clip
    // would strand an UNENCRYPTED copy of its content in tmp, outside the
    // SQLCipher + AES-GCM boundary the rest of the store maintains. The
    // staging lifecycle closes that hole: assets stage in one dedicated
    // directory, the sync adapter deletes each record's file the moment
    // CloudKit reports it sent, and a start-time sweep reaps stragglers from
    // crashed or failed sends.
    //
    // Staged files are deliberately NOT wrapped in `SealedEnvelope`: CloudKit
    // uploads the staged file's bytes VERBATIM as the asset payload, so a
    // sealed file would sync ciphertext — undecryptable on the receiving
    // device — as the clip's content (and `decode` reads the fetched asset
    // from CloudKit-managed storage, expecting the original bytes). CloudKit
    // already encrypts CKAsset payloads in transit and at rest server-side;
    // the local plaintext window is bounded by the lifecycle above.

    /// The directory `makeAsset` stages binary payloads in. Everything in it
    /// is plaintext clip content awaiting upload — transient by contract.
    public static var assetStagingDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("gancho-ck-assets", isDirectory: true)
    }

    /// Deletes the staged file behind a record's `contentAsset`, if the asset
    /// points into ``assetStagingDirectory``. Call once CloudKit no longer
    /// needs the file (the record was reported sent). Assets on *fetched*
    /// records live in CloudKit-managed storage and are left alone.
    public static func removeStagedAsset(for record: CKRecord) {
        guard let asset = record["contentAsset"] as? CKAsset, let url = asset.fileURL else {
            return
        }
        // Resolve symlinks before comparing: temporaryDirectory routes through
        // /var → /private/var on Darwin, and the CKAsset may hand back either
        // form. Only files strictly inside the staging directory are deleted.
        let staging = assetStagingDirectory.resolvingSymlinksInPath().standardizedFileURL
        let file = url.resolvingSymlinksInPath().standardizedFileURL
        guard file.deletingLastPathComponent().path == staging.path else { return }
        try? FileManager.default.removeItem(at: file)
    }

    /// Removes staged assets older than `maxAge` — files orphaned by a crash
    /// or a failed send between staging and the sent-record event. Recent
    /// files are left alone: they may belong to a batch CloudKit has not read
    /// yet, and deleting one would drop its upload.
    public static func sweepStagedAssets(olderThan maxAge: TimeInterval = 3600) {
        let fileManager = FileManager.default
        guard
            let files = try? fileManager.contentsOfDirectory(
                at: assetStagingDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }
        for file in files {
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey])
            guard let modified = values?.contentModificationDate else { continue }
            if Date.now.timeIntervalSince(modified) > maxAge {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    private static func makeAsset(_ data: Data) -> CKAsset? {
        let directory = assetStagingDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("gancho-asset-\(UUID().uuidString)")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return CKAsset(fileURL: url)
    }

    private static func decodeTags(_ json: String?) -> [String] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}
