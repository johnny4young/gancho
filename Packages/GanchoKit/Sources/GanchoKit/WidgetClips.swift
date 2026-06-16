import Foundation

/// A clip as a widget shows it on the home/lock screen. Deliberately tiny and
/// `Sendable`: it carries only what a glanceable row needs and NEVER the raw
/// content of a sensitive clip (the masking happens when the entry is built,
/// so a secret can't reach the lock screen even if the view is careless).
public struct WidgetClipEntry: Identifiable, Sendable, Equatable, Codable {
    public let id: UUID
    /// Title for non-sensitive clips; empty for sensitive ones.
    public let title: String
    /// One-line text safe to render anywhere — masked (`•••`) for sensitive clips.
    public let displayText: String
    public let kind: ClipContentKind
    public let isSensitive: Bool

    public init(
        id: UUID, title: String, displayText: String, kind: ClipContentKind, isSensitive: Bool
    ) {
        self.id = id
        self.title = title
        self.displayText = displayText
        self.kind = kind
        self.isSensitive = isSensitive
    }

    /// Deep-link URL that opens this clip in the app (`gancho://clip/<id>`).
    public var deepLinkURL: URL? {
        URL(string: "gancho://clip/\(id.uuidString)")
    }
}

/// Builds widget entries from clips. The single place the home/lock-screen
/// masking rule lives: a sensitive clip is reduced to `•••` with no title, so
/// the secret never travels into a widget timeline (which the system may cache
/// and render on a locked device).
public enum WidgetClips {
    public static let masked = "•••"

    public static func entries(from items: [ClipItem], limit: Int = 3) -> [WidgetClipEntry] {
        items.prefix(limit).map { item in
            if item.isSensitive {
                return WidgetClipEntry(
                    id: item.id, title: "", displayText: masked, kind: item.kind,
                    isSensitive: true)
            }
            let body = item.preview.isEmpty ? item.title : item.preview
            return WidgetClipEntry(
                id: item.id, title: item.title, displayText: body, kind: item.kind,
                isSensitive: false)
        }
    }

    /// Parses a `gancho://clip/<uuid>` deep link back into a clip id.
    public static func clipID(fromDeepLink url: URL) -> UUID? {
        guard url.scheme == "gancho", url.host == "clip" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}
