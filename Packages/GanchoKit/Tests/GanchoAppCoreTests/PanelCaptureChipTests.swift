import Foundation
import Testing

@testable import GanchoAppCore

@Suite("Footer capture chip and paste label")
struct PanelCaptureChipTests {
    private func chip(
        _ status: PanelCaptureRuntimeStatus, privateMode: Bool = false, endsAt: Date? = nil,
        frontApp: String? = "Figma"
    ) -> PanelCaptureChip {
        PanelCaptureChip.resolve(
            privateModeEnabled: privateMode, privateModeEndsAt: endsAt, runtimeStatus: status,
            frontApp: frontApp)
    }

    @Test("Running capture names the app in front, or nothing when there is none")
    func capturing() {
        #expect(chip(.running) == .capturing(frontApp: "Figma"))
        #expect(chip(.running, frontApp: nil) == .capturing(frontApp: nil))
    }

    @Test("Each pause names its cause")
    func pauses() {
        #expect(chip(.pausedByScreenShare) == .paused(.screenShare))
        #expect(chip(.pausedByScreenLock) == .paused(.screenLock))
        #expect(chip(.pausedByUser) == .paused(.user))
        #expect(chip(.stopped) == .paused(.user))
    }

    @Test("Private Mode outranks pauses, and denied access outranks Private Mode")
    func precedence() {
        let end = Date(timeIntervalSince1970: 3_600)
        #expect(chip(.pausedByUser, privateMode: true, endsAt: end) == .privateMode(endsAt: end))
        #expect(chip(.pausedByScreenShare, privateMode: true) == .privateMode(endsAt: nil))
        #expect(chip(.deniedByPrivacySettings, privateMode: true) == .denied)
    }

    @Test("Minutes left round up and never reach zero while on")
    func minutesLeft() {
        let now = Date(timeIntervalSince1970: 0)
        #expect(
            PanelCaptureChip.minutesLeft(until: now.addingTimeInterval(58 * 60), now: now) == 58)
        #expect(PanelCaptureChip.minutesLeft(until: now.addingTimeInterval(61), now: now) == 2)
        #expect(PanelCaptureChip.minutesLeft(until: now.addingTimeInterval(5), now: now) == 1)
        #expect(PanelCaptureChip.minutesLeft(until: now, now: now) == 1)
    }

    @Test(
        "The paste button names its target, falls back to Paste, and says Copy without Accessibility"
    )
    func pasteLabel() {
        #expect(
            PanelPasteLabel.resolve(targetApp: "Figma", canPostPaste: true) == .pasteInto("Figma"))
        #expect(PanelPasteLabel.resolve(targetApp: nil, canPostPaste: true) == .paste)
        #expect(PanelPasteLabel.resolve(targetApp: "", canPostPaste: true) == .paste)
        #expect(PanelPasteLabel.resolve(targetApp: "Figma", canPostPaste: false) == .copy)
        #expect(PanelPasteLabel.resolve(targetApp: nil, canPostPaste: false) == .copy)
    }
}
