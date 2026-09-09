import Foundation

/// Publishes a fully written staged file at its final path, atomically.
///
/// `Data.write(options: .atomic)` already does this for anything small enough
/// to hold in memory. This exists for the writers that CANNOT: a streamed
/// export builds its file incrementally, so it stages under a temporary name
/// and swaps at the end.
///
/// `rename(2)` both replaces an existing destination and is atomic, which
/// `FileManager.moveItem` (fails when the destination exists) and
/// `replaceItemAt` (throws when it does not) each get only half right. Doing it
/// by hand as remove-then-move is worse than either: readers can observe the
/// destination missing, and a failure after the remove destroys the previous
/// good file while stranding the staged one.
///
/// On failure the staged file is removed, so a failed publish leaves exactly
/// what was there before and nothing else.
enum AtomicFileReplace {
    static func publish(staged: URL, as destination: URL) throws {
        let renamed = staged.withUnsafeFileSystemRepresentation { source in
            destination.withUnsafeFileSystemRepresentation { target in
                guard let source, let target else { return false }
                return rename(source, target) == 0
            }
        }
        guard renamed else {
            try? FileManager.default.removeItem(at: staged)
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
