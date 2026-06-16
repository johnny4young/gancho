import Foundation

/// Human-readable byte sizes for previews and messages — "717 KB", "12.4 MB"
/// instead of a raw byte count. File style (1000-based, like Finder) auto-picks
/// the unit, so small payloads read in KB and large ones in MB.
public enum ByteSize {
    public static func formatted(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// Display-time humanizer: turns a stored `"Image (734053 bytes)"` preview
    /// into `"Image (717 KB)"`, and passes anything else through unchanged.
    /// This makes OLD or synced-in clips render with readable sizes without
    /// rewriting stored data, independent of when they were captured.
    public static func humanizedPreview(_ preview: String) -> String {
        guard let bytes = legacyImageByteCount(preview) else { return preview }
        return "Image (\(formatted(bytes)))"
    }

    /// The trailing digit run before `" bytes)"` in an `"Image (… bytes)"`
    /// preview (handles both "Image (N bytes)" and "Image (uti, N bytes)").
    static func legacyImageByteCount(_ preview: String) -> Int? {
        guard preview.hasPrefix("Image ("), let tail = preview.range(of: " bytes)") else {
            return nil
        }
        let digits = String(
            preview[..<tail.lowerBound].reversed().prefix { $0.isNumber }.reversed())
        return Int(digits)
    }
}
