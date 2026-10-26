import Testing

@testable import GanchoDesign

@Suite("SourceAppTile — letter and colour")
struct SourceAppTileTests {
    @Test("The initial of the app's readable name")
    func letter() {
        #expect(SourceAppTile.letter(forBundleID: "com.apple.mobilesafari") == "S")
        #expect(SourceAppTile.letter(forBundleID: "com.apple.dt.Xcode") == "X")
        #expect(SourceAppTile.letter(forBundleID: "com.example.1password") == "1")
        #expect(SourceAppTile.letter(forBundleID: "com.example._") == "•")
        #expect(SourceAppTile.letter(forBundleID: "") == "•")
    }

    @Test("The same app always picks the same colour, and apps spread over the palette")
    func stableColour() {
        let id = "com.apple.dt.Xcode"
        // Pinned, so a per-launch hash would fail here rather than on a device.
        #expect(SourceAppTile.colorOption(forBundleID: id) == .teal)
        #expect(
            SourceAppTile.colorOption(forBundleID: "com.apple.Safari")
                == SourceAppTile.colorOption(forBundleID: "com.apple.mobilesafari"),
            "one app, one colour, whichever platform copied it")
        let ids = (0..<40).map { "com.example.app\($0)" }
        let picked = Set(ids.map { SourceAppTile.colorOption(forBundleID: $0) })
        #expect(picked.count > 1)
    }
}
