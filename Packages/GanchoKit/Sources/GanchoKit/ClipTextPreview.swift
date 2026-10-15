/// A grapheme-safe preview that visits only the visible prefix. Counting a
/// multi-megabyte clip before truncating it repeats a full scan on every render.
public enum ClipTextPreview {
    public static func truncated(_ text: String, limit: Int) -> String {
        guard
            let end = text.index(
                text.startIndex, offsetBy: max(0, limit), limitedBy: text.endIndex),
            end != text.endIndex
        else { return text }
        return String(text[..<end]) + "\n…"
    }
}
