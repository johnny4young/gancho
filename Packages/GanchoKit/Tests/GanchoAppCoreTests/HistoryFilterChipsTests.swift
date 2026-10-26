import Testing

@testable import GanchoAppCore

@Suite("History filter chips — active type and app filters as chips")
struct HistoryFilterChipsTests {
    @Test("Type first, then app; nothing active means no row")
    func chips() {
        #expect(HistoryFilterChip.chips(kind: nil, appBundleID: nil).isEmpty)
        #expect(HistoryFilterChip.chips(kind: nil, appBundleID: "").isEmpty)
        #expect(HistoryFilterChip.chips(kind: .url, appBundleID: nil) == [.kind(.url)])
        #expect(
            HistoryFilterChip.chips(kind: .url, appBundleID: "com.apple.mobilesafari")
                == [.kind(.url), .app(bundleID: "com.apple.mobilesafari")])
    }
}
