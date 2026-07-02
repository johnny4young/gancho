import CryptoKit
import Foundation
import ImageIO

/// Content-addressed blob storage for binary clip payloads.
///
/// Files are named by their SHA-256, so identical content is stored once
/// and references can never dangle silently. Encrypted stores keep both blob
/// payloads and cached thumbnails sealed at rest. Thumbnails are generated
/// LAZILY via ImageIO's downsampling (`kCGImageSourceThumbnailMaxPixelSize`)
/// which decodes at target size — the full-resolution bitmap NEVER enters
/// memory for list rendering. The full blob is read only for paste-back.
public struct BlobStore: Sendable {
    public let directory: URL
    let encryptionKeyData: Data?

    /// Sealed-file header. Owned by `SealedEnvelope` (the shared primitive
    /// this framing was extracted into); aliased here for the header checks.
    static let encryptedMagic = SealedEnvelope.magic

    /// Sentinel (hidden, so directory scans skip it) written once the blobs +
    /// thumbnails have been migrated to the sealed format, so later opens don't
    /// re-scan every file. New writes always seal, so nothing plaintext reappears.
    static let migrationMarker = ".blobs-encrypted"

    private var thumbnailDirectory: URL {
        directory.appendingPathComponent("thumbnails", isDirectory: true)
    }

    /// Thumbnail bounding box in pixels. 256 covers list rows on Retina.
    public static let thumbnailMaxPixelSize = 256

    /// Byte ceiling for warm-at-write thumbnail generation. Payloads above
    /// this build their thumbnail lazily on first request (the cold-cache
    /// path in `thumbnailData(for:)`), so a burst of large image captures
    /// never gates the store write on an ImageIO decode/encode.
    static let thumbnailWarmMaxBytes = 8 << 20

    public init(directory: URL, encryptionKeyData: Data? = nil) {
        self.directory = directory
        self.encryptionKeyData = encryptionKeyData
    }

    static func encryptionKeyData(for passphrase: String) -> Data {
        let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count == 64, let decoded = Data(hexEncoded: trimmed) {
            return decoded
        }
        // Derive from the SAME trimmed string the hex path uses, so a stray
        // trailing newline can't yield a different key for the same passphrase.
        return Data(SHA256.hash(data: Data(trimmed.utf8)))
    }

    /// Stores the data (idempotent) and returns its content hash reference.
    @discardableResult
    public func write(_ data: Data) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let file = blobURL(for: hash)
        // Re-encode only when the file is missing or a pre-encryption plaintext
        // blob; an existing sealed (or key-less) blob is already correct. The
        // check reads the header bytes, never the whole file.
        let needsWrite =
            !FileManager.default.fileExists(atPath: file.path)
            || (encryptionKeyData != nil && !Self.isEncryptedFileOnDisk(file))
        if needsWrite {
            try encodeForDisk(data).write(to: file, options: .atomic)
        }
        // Warm the thumbnail from the in-memory data so memory-tight readers
        // (the keyboard) never load the full blob just to build it. Large
        // payloads skip the warm pass — their ImageIO work would gate the
        // capture write — and warm lazily on first request instead.
        if data.count <= Self.thumbnailWarmMaxBytes {
            try cacheThumbnail(for: hash, from: data)
        }
        return hash
    }

    /// Full blob — paste-back only; UI code must use thumbnail helpers.
    public func read(hash: String) throws -> Data? {
        let file = blobURL(for: hash)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try decodeFromDisk(Data(contentsOf: file))
    }

    public func delete(hash: String) {
        try? FileManager.default.removeItem(at: blobURL(for: hash))
        try? FileManager.default.removeItem(at: thumbnailURLIfCached(for: hash))
    }

    /// Lazy thumbnail data: generated on first request, cached on disk after.
    /// Cached bytes are encrypted when the store has an encryption key.
    /// Returns nil when the blob is missing or not an image.
    public func thumbnailData(for hash: String) throws -> Data? {
        let cached = thumbnailURLIfCached(for: hash)
        if !FileManager.default.fileExists(atPath: cached.path) {
            // Cold cache (a pre-feature blob, or one not warmed at write time):
            // build it from the full blob once, then read the small cache back.
            guard let data = try read(hash: hash) else { return nil }
            try cacheThumbnail(for: hash, from: data)
        }
        guard FileManager.default.fileExists(atPath: cached.path) else { return nil }
        return try decodeFromDisk(Data(contentsOf: cached))
    }

    /// Generate and cache the thumbnail from in-memory data (at capture/import
    /// time), sealed when the store has a key. Idempotent; a no-op for
    /// non-images or when the thumbnail is already cached.
    func cacheThumbnail(for hash: String, from data: Data) throws {
        let cached = thumbnailURLIfCached(for: hash)
        guard !FileManager.default.fileExists(atPath: cached.path),
            let thumbnail = Self.makeThumbnailData(from: data)
        else { return }
        try FileManager.default.createDirectory(
            at: thumbnailDirectory, withIntermediateDirectories: true)
        try encodeForDisk(thumbnail).write(to: cached, options: .atomic)
    }

    /// Lazy plaintext thumbnail file URL for non-encrypted stores. Encrypted
    /// stores should use `thumbnailData(for:)` so cached files stay sealed.
    /// Returns nil when the blob is missing, not an image, or encrypted.
    public func thumbnailURL(for hash: String) throws -> URL? {
        guard encryptionKeyData == nil else { return nil }
        let cached = thumbnailURLIfCached(for: hash)
        if FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }

        let blob = blobURL(for: hash)
        guard FileManager.default.fileExists(atPath: blob.path),
            let source = CGImageSourceCreateWithURL(blob as CFURL, nil),
            let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: Self.thumbnailMaxPixelSize,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                ] as CFDictionary)
        else { return nil }

        try FileManager.default.createDirectory(
            at: thumbnailDirectory, withIntermediateDirectories: true)
        guard
            let destination = CGImageDestinationCreateWithURL(
                cached as CFURL, "public.png" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return cached
    }

    /// Encrypts existing plaintext blob and thumbnail files in place. This is
    /// used when a pre-encryption store first opens with an encryption key.
    func encryptPlaintextFilesIfNeeded() throws {
        guard encryptionKeyData != nil else { return }
        let marker = directory.appendingPathComponent(Self.migrationMarker)
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        try encryptPlaintextFiles(in: directory)
        try encryptPlaintextFiles(in: thumbnailDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: marker.path, contents: Data())
    }

    /// Sweeps every blob whose hash is NOT in `referenced` (and its cached
    /// thumbnail). Returns how many blobs were removed. Mass purges delete
    /// rows by SQL, so orphan cleanup happens here.
    public func removeAll(except referenced: Set<String>) -> Int {
        let files =
            (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        var removed = 0
        for name in files
        where name != "thumbnails" && name != Self.migrationMarker
            && !referenced.contains(name)
        {
            delete(hash: name)
            removed += 1
        }
        return removed
    }

    private func blobURL(for hash: String) -> URL {
        directory.appendingPathComponent(hash)
    }

    private func thumbnailURLIfCached(for hash: String) -> URL {
        thumbnailDirectory.appendingPathComponent("\(hash).png")
    }

    private func encryptPlaintextFiles(in directory: URL) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles])
        for file in files {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            // Read the header only; the whole file is read just for the plaintext
            // files that actually need re-encrypting (rare after the first pass).
            guard !Self.isEncryptedFileOnDisk(file) else { continue }
            let stored = try Data(contentsOf: file)
            try encodeForDisk(stored).write(to: file, options: .atomic)
        }
    }

    private func encodeForDisk(_ data: Data) throws -> Data {
        guard let encryptionKeyData else { return data }
        return try SealedEnvelope.seal(data, key: encryptionKeyData)
    }

    private func decodeFromDisk(_ data: Data) throws -> Data {
        guard SealedEnvelope.isSealed(data) else { return data }
        guard let encryptionKeyData else { throw BlobStoreError.missingEncryptionKey }
        return try SealedEnvelope.open(data, key: encryptionKeyData)
    }

    /// Header-only magic check — reads `encryptedMagic.count` bytes, not the
    /// whole file. Matters at launch (the migration scan touches every blob) and
    /// in the memory-tight keyboard extension.
    private static func isEncryptedFileOnDisk(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let header = (try? handle.read(upToCount: encryptedMagic.count)) ?? Data()
        return header.count == encryptedMagic.count && header.elementsEqual(encryptedMagic)
    }

    private static func makeThumbnailData(from data: Data) -> Data? {
        guard
            let source = CGImageSourceCreateWithData(
                data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
            let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: Self.thumbnailMaxPixelSize,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                ] as CFDictionary)
        else { return nil }

        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, "public.png" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

private enum BlobStoreError: Error {
    case missingEncryptionKey
}

extension Data {
    fileprivate init?(hexEncoded string: String) {
        guard string.count.isMultiple(of: 2) else { return nil }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(string.count / 2)

        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(index, offsetBy: 2)
            guard let byte = UInt8(string[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }
}
