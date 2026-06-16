import Foundation

/// Human-readable byte sizes for previews and messages — "717 KB", "12.4 MB"
/// instead of a raw byte count. File style (1000-based, like Finder) auto-picks
/// the unit, so small payloads read in KB and large ones in MB.
public enum ByteSize {
    public static func formatted(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
