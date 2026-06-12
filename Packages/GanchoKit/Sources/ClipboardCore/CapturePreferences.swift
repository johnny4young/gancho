import Foundation

/// User-controlled capture knobs, persisted as one JSON blob under a single
/// defaults key (atomic load/save, easy migration). The Settings UI binds to
/// this; the monitor only consumes it — ownership stays with the app layer.
public struct CapturePreferences: Sendable, Equatable, Codable {
    /// Capture PNG/TIFF payloads. Off ⇒ image-only copies are skipped
    /// BEFORE the content read (their types give them away).
    public var captureImages: Bool
    /// Capture file references copied in Finder.
    public var captureFileReferences: Bool
    /// Keep RTF/HTML fidelity. Off ⇒ rich payloads degrade to their plain
    /// text companion instead of being dropped.
    public var captureRichText: Bool
    /// Private mode: capture is fully paused, and anything copied while
    /// paused is NEVER captured retroactively on resume.
    public var isPrivateModePaused: Bool

    public init(
        captureImages: Bool = true,
        captureFileReferences: Bool = true,
        captureRichText: Bool = true,
        isPrivateModePaused: Bool = false
    ) {
        self.captureImages = captureImages
        self.captureFileReferences = captureFileReferences
        self.captureRichText = captureRichText
        self.isPrivateModePaused = isPrivateModePaused
    }

    private static let defaultsKey = "capture-preferences"

    /// Missing or corrupt data falls back to defaults — preferences are not
    /// worth failing capture over.
    public static func load(from defaults: UserDefaults) -> CapturePreferences {
        guard let data = defaults.data(forKey: defaultsKey),
            let prefs = try? JSONDecoder().decode(CapturePreferences.self, from: data)
        else { return CapturePreferences() }
        return prefs
    }

    public func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
