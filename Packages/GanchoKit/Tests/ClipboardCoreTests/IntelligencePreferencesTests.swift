import Foundation
import Testing

@testable import ClipboardCore

@Suite("Intelligence preferences")
struct IntelligencePreferencesTests {
    @Test("Defaults: every enrichment toggle starts on")
    func defaultsAllOn() {
        let prefs = IntelligencePreferences()
        #expect(prefs.intelligentTitles)
        #expect(prefs.semanticSearch)
        #expect(prefs.searchableScreenshots)
        #expect(prefs.detectSecrets)
    }

    @Test("Round-trips through UserDefaults, preserving each toggle")
    func roundTrips() throws {
        let defaults = try #require(UserDefaults(suiteName: "intel-\(UUID().uuidString)"))
        var prefs = IntelligencePreferences()
        prefs.semanticSearch = false
        prefs.detectSecrets = false
        prefs.save(to: defaults)

        let loaded = IntelligencePreferences.load(from: defaults)
        #expect(loaded == prefs)
        #expect(loaded.intelligentTitles)  // untouched stays on
        #expect(!loaded.semanticSearch)
        #expect(!loaded.detectSecrets)
    }

    @Test("Decoding tolerates missing keys — a newly added toggle defaults on")
    func decodeMissingKeysDefaultsOn() throws {
        // An older blob that only knew about one key must not flip the rest off.
        let json = Data(#"{"semanticSearch":false}"#.utf8)
        let prefs = try JSONDecoder().decode(IntelligencePreferences.self, from: json)
        #expect(!prefs.semanticSearch)  // honored
        #expect(prefs.intelligentTitles)  // missing → default on
        #expect(prefs.searchableScreenshots)
        #expect(prefs.detectSecrets)
    }

    @Test("Missing or corrupt blob loads as the all-on default")
    func missingBlobDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "intel-empty-\(UUID().uuidString)"))
        #expect(IntelligencePreferences.load(from: defaults) == IntelligencePreferences())
    }
}
