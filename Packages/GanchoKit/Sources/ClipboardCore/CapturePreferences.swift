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
    /// When the current Private Mode began; nil when it is off or predates the stamp.
    public var privateModeStartedAt: Date?
    /// When Private Mode turns itself off; nil means it stays on until the user turns it off.
    public var privateModeEndsAt: Date?
    /// Copies made during the current Private Mode, counted from the change
    /// count alone: their content is never read.
    public var privateModeSkippedCopies: Int

    public init(
        captureImages: Bool = true,
        captureFileReferences: Bool = true,
        captureRichText: Bool = true,
        isPrivateModePaused: Bool = false,
        privateModeStartedAt: Date? = nil,
        privateModeEndsAt: Date? = nil,
        privateModeSkippedCopies: Int = 0
    ) {
        self.captureImages = captureImages
        self.captureFileReferences = captureFileReferences
        self.captureRichText = captureRichText
        self.isPrivateModePaused = isPrivateModePaused
        self.privateModeStartedAt = privateModeStartedAt
        self.privateModeEndsAt = privateModeEndsAt
        self.privateModeSkippedCopies = privateModeSkippedCopies
    }

    /// Blobs saved before the Private Mode timer decode with it unset.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        captureImages = try container.decode(Bool.self, forKey: .captureImages)
        captureFileReferences = try container.decode(Bool.self, forKey: .captureFileReferences)
        captureRichText = try container.decode(Bool.self, forKey: .captureRichText)
        isPrivateModePaused = try container.decode(Bool.self, forKey: .isPrivateModePaused)
        privateModeStartedAt = try container.decodeIfPresent(
            Date.self, forKey: .privateModeStartedAt)
        privateModeEndsAt = try container.decodeIfPresent(Date.self, forKey: .privateModeEndsAt)
        privateModeSkippedCopies =
            try container.decodeIfPresent(Int.self, forKey: .privateModeSkippedCopies) ?? 0
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

/// How long Private Mode stays on before capture resumes by itself.
public enum PrivateModeAutoOff: Int, Sendable, CaseIterable, Identifiable {
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case twoHours = 120
    case never = 0

    public static let defaultsKey = "private-mode-auto-off-minutes"
    public static let standard = Self.oneHour

    public var id: Int { rawValue }

    /// Nil keeps Private Mode on until the user turns it off.
    public var duration: TimeInterval? {
        self == .never ? nil : TimeInterval(rawValue * 60)
    }

    public static func load(from defaults: UserDefaults) -> Self {
        (defaults.object(forKey: defaultsKey) as? Int).flatMap(Self.init(rawValue:)) ?? standard
    }
}
