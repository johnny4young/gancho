import Darwin
import Foundation

/// A complete archive is published with one same-filesystem namespace change.
/// Existing archives are exchanged atomically, never removed before promotion.
/// The old archive lands in the owned stage and can be recovered after a crash.
enum AtomicArchivePublication {
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
        _ stage: URL, as destination: URL, replacement: GanchoArchive.ReplacementPolicy
    ) throws {
        let installed = rename(stage, to: destination, flags: UInt32(RENAME_EXCL))
        if installed == 0 { return }
        let failure = errno
        guard failure == EEXIST, replacement == .replaceExisting else {
            throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw CocoaError(.fileWriteFileExists)
        }
        guard rename(stage, to: destination, flags: UInt32(RENAME_SWAP)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        // Cleanup belongs to the caller's stage defer. It is best-effort after
        // successful promotion: cleanup failure must not report export failure
        // after the destination has already changed.
    }

    private static func rename(_ source: URL, to destination: URL, flags: UInt32) -> Int32 {
        source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                guard let sourcePath, let destinationPath else { errno = EINVAL; return -1 }
                return renameatx_np(AT_FDCWD, sourcePath, AT_FDCWD, destinationPath, flags)
            }
        }
    }
}
