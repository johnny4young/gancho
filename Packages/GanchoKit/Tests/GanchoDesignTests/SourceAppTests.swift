import Testing

@testable import GanchoDesign

/// The live name/icon lookup needs an installed app, so these cover the pure
/// fallback that drives the history's "From …" insight when an app can't be
/// resolved (uninstalled source, sandboxed lookup, or tests).
@Suite("SourceApp fallback name")
struct SourceAppTests {
    @Test("Uses the last bundle-id segment, capitalized")
    func lastSegment() {
        #expect(SourceApp.fallbackName(forBundleID: "com.apple.Terminal") == "Terminal")
        #expect(SourceApp.fallbackName(forBundleID: "com.google.Chrome") == "Chrome")
        #expect(SourceApp.fallbackName(forBundleID: "com.microsoft.VSCode") == "VSCode")
    }

    @Test("Recognizes platform bundle aliases")
    func platformAliases() {
        #expect(SourceApp.fallbackName(forBundleID: "com.apple.mobilesafari") == "Safari")
        #expect(SourceApp.fallbackName(forBundleID: "com.apple.dt.Xcode") == "Xcode")
    }

    @Test(
        "A platform suffix gives way to the app's name",
        arguments: [
            ("com.figma.Desktop", "Figma"), ("com.example.notes.macOS", "Notes"),
            ("com.example.Reader.iOS", "Reader"), ("io.example.App", "Example"),
            ("Desktop", "Desktop"), ("app.Desktop", "Desktop")
        ])
    func platformSuffix(bundleID: String, name: String) {
        #expect(SourceApp.fallbackName(forBundleID: bundleID) == name)
    }

    @Test("A dotless id stays as-is; a single char is capitalized; empty is safe")
    func edges() {
        #expect(SourceApp.fallbackName(forBundleID: "Finder") == "Finder")
        #expect(SourceApp.fallbackName(forBundleID: "x") == "X")
        #expect(SourceApp.fallbackName(forBundleID: "").isEmpty)
    }
}
