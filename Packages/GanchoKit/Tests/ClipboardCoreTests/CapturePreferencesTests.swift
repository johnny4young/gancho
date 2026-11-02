import Foundation
import Testing

@testable import ClipboardCore

@Suite("Capture preferences — stored blob compatibility")
struct CapturePreferencesTests {
    @Test("A blob saved before the Private Mode timer keeps its choices")
    func legacyBlobDecodes() throws {
        let legacy = Data(
            #"{"captureImages":false,"captureFileReferences":true,"captureRichText":true,"isPrivateModePaused":true}"#
                .utf8)
        let prefs = try JSONDecoder().decode(CapturePreferences.self, from: legacy)
        #expect(!prefs.captureImages)
        #expect(prefs.isPrivateModePaused)
        #expect(prefs.privateModeStartedAt == nil)
        #expect(prefs.privateModeEndsAt == nil)
        #expect(prefs.privateModeSkippedCopies == 0)
    }

    @Test("Auto-off defaults to one hour, and Until I turn it off has no deadline")
    func autoOffChoices() throws {
        let defaults = try #require(UserDefaults(suiteName: "auto-off-\(UUID().uuidString)"))
        #expect(PrivateModeAutoOff.load(from: defaults) == .oneHour)
        #expect(PrivateModeAutoOff.oneHour.duration == 3_600)
        defaults.set(0, forKey: PrivateModeAutoOff.defaultsKey)
        #expect(PrivateModeAutoOff.load(from: defaults).duration == nil)
        defaults.set(7, forKey: PrivateModeAutoOff.defaultsKey)
        #expect(PrivateModeAutoOff.load(from: defaults) == .oneHour, "an unknown value falls back")
    }

    @Test("The timer and the count survive a save and load")
    func roundTrip() throws {
        let defaults = try #require(UserDefaults(suiteName: "capture-prefs-\(UUID().uuidString)"))
        let start = Date(timeIntervalSince1970: 1_000)
        let saved = CapturePreferences(
            isPrivateModePaused: true, privateModeStartedAt: start,
            privateModeEndsAt: start.addingTimeInterval(3_600), privateModeSkippedCopies: 3)
        saved.save(to: defaults)
        #expect(CapturePreferences.load(from: defaults) == saved)
    }

    @Test("Double-copy merging is off and its sound on, by default and in older blobs")
    func mergeDefaults() throws {
        #expect(!CapturePreferences().mergeDoubleCopies)
        #expect(CapturePreferences().playsMergeSound)
        let old = Data(
            #"{"captureImages":true,"captureFileReferences":true,"captureRichText":true,"isPrivateModePaused":false}"#
                .utf8)
        let decoded = try JSONDecoder().decode(CapturePreferences.self, from: old)
        #expect(!decoded.mergeDoubleCopies)
        #expect(decoded.playsMergeSound)
    }
}
