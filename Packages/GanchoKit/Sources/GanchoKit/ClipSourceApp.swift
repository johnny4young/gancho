import Foundation

/// Content-free metadata for one app represented in visible clip history.
/// The bundle identifier is the stable filter value; `clipCount` is aggregate
/// metadata only, so source-app discovery never needs to load clipboard text.
public struct ClipSourceApp: Identifiable, Hashable, Sendable {
    public let bundleID: String
    public let clipCount: Int

    public var id: String { bundleID }

    public init(bundleID: String, clipCount: Int) {
        self.bundleID = bundleID
        self.clipCount = clipCount
    }
}
