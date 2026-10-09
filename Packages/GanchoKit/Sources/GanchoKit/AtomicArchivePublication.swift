import Darwin
import Foundation

/// A complete archive is published with one same-filesystem namespace change.
/// Existing archives are exchanged atomically, never removed before promotion.
/// The old archive lands in the owned stage and can be recovered after a crash.
enum AtomicArchivePublication {
    /// One `renameatx_np` call: 0 on success, otherwise the `errno` it failed with.
    typealias Renamer = @Sendable (_ source: URL, _ destination: URL, _ flags: UInt32) -> Int32

    static func makeStage(beside destination: URL) throws -> URL {
        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let stage = parent.appendingPathComponent(".ganchoarchive-stage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: stage, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        return stage
    }

    static func publish(
        _ stage: URL, as destination: URL, replacement: GanchoArchive.ReplacementPolicy,
        renamer: Renamer = AtomicArchivePublication.systemRename
    ) throws {
        let exclusive = renamer(stage, destination, UInt32(RENAME_EXCL))
        if exclusive == 0 { return }
        if exclusive == ENOTSUP || exclusive == EINVAL {
            // exFAT, FAT and some SMB volumes cannot rename exclusively. Only a
            // NEW destination may fall back; there is no previous archive to
            // protect there, and replacement still requires an atomic exchange.
            guard !itemExists(at: destination) else {
                throw CocoaError(.fileWriteFileExists)
            }
            let plain = renamer(stage, destination, 0)
            guard plain == 0 else { throw posixError(plain) }
            return
        }
        guard exclusive == EEXIST, replacement == .replaceExisting else {
            throw posixError(exclusive)
        }
        try requireReplaceableArchive(at: destination)
        let swapped = renamer(stage, destination, UInt32(RENAME_SWAP))
        guard swapped == 0 else { throw posixError(swapped) }
        // Cleanup belongs to the caller's stage defer. It is best-effort after
        // successful promotion: cleanup failure must not report export failure
        // after the destination has already changed.
    }

    /// Refuses, before any export work, a destination that `publish` could
    /// never accept. `publish` repeats the checks at promotion time, so this
    /// only spares streaming the whole history into a stage that is discarded.
    static func requirePublishable(
        _ destination: URL, replacement: GanchoArchive.ReplacementPolicy
    ) throws {
        guard itemExists(at: destination) else { return }
        guard replacement == .replaceExisting else { throw CocoaError(.fileWriteFileExists) }
        try requireReplaceableArchive(at: destination)
    }

    /// Replacement exchanges the whole directory and the caller then deletes
    /// the old one, so only a previous Gancho archive (its `manifest.json`
    /// decodes as a Gancho manifest) or an empty folder may be replaced. Any
    /// other folder a save panel lets the user name, including one that merely
    /// holds an unrelated `manifest.json`, is refused untouched.
    static func requireReplaceableArchive(at destination: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw CocoaError(.fileWriteFileExists)
        }
        let entries = try FileManager.default.contentsOfDirectory(atPath: destination.path)
            .filter { $0 != ".DS_Store" }
        guard entries.isEmpty || GanchoArchive.containsArchiveManifest(destination) else {
            throw CocoaError(.fileWriteFileExists)
        }
    }

    static let systemRename: Renamer = { source, destination, flags in
        source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                guard let sourcePath, let destinationPath else { return EINVAL }
                let result = renameatx_np(
                    AT_FDCWD, sourcePath, AT_FDCWD, destinationPath, flags)
                return result == 0 ? 0 : errno
            }
        }
    }

    /// `lstat`-based: a dangling symlink still counts as an existing item.
    private static func itemExists(at url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    private static func posixError(_ code: Int32) -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
}
