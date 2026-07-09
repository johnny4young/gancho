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

    @Test("A dotless id stays as-is; a single char is capitalized; empty is safe")
    func edges() {
        #expect(SourceApp.fallbackName(forBundleID: "Finder") == "Finder")
        #expect(SourceApp.fallbackName(forBundleID: "x") == "X")
        #expect(SourceApp.fallbackName(forBundleID: "").isEmpty)
    }
}
