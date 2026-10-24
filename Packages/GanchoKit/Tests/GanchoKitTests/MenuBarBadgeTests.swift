import Testing

@testable import GanchoKit

@Suite("Menu-bar badge — one state on the hook, by precedence")
struct MenuBarBadgeTests {
    private func badge(
        denied: Bool = false, paused: Bool = false, privateMode: Bool = false,
        ignoring: Bool = false, stack: Int = 0
    ) -> MenuBarBadge? {
        MenuBarBadge.resolve(
            denied: denied, paused: paused, privateMode: privateMode, ignoresNextCopy: ignoring,
            stackCount: stack)
    }

    @Test("Capturing with nothing waiting is the bare hook")
    func capturingHasNoBadge() {
        #expect(badge() == nil)
    }

    @Test("Denied > paused > private > ignore-next > stack")
    func precedence() {
        #expect(
            badge(denied: true, paused: true, privateMode: true, ignoring: true, stack: 2)
                == .denied)
        #expect(badge(paused: true, privateMode: true, ignoring: true, stack: 2) == .paused)
        #expect(badge(privateMode: true, ignoring: true, stack: 2) == .privateMode)
        #expect(badge(ignoring: true, stack: 2) == .ignoreNext)
        #expect(badge(stack: 2) == .stack(2))
    }

    @Test("Glyphs, with a stack past nine reading 9+")
    func glyphs() {
        #expect(MenuBarBadge.denied.glyph == "!")
        #expect(MenuBarBadge.paused.glyph == "‖")
        #expect(MenuBarBadge.privateMode.glyph == "/")
        #expect(MenuBarBadge.ignoreNext.glyph == "−")
        #expect(MenuBarBadge.stack(9).glyph == "9")
        #expect(MenuBarBadge.stack(12).glyph == "9+")
    }

    @Test("⌥ pauses or resumes, ⌥⇧ ignores the next copy, a plain click opens the menu")
    func clicks() {
        #expect(MenuBarClick(option: false, shift: false) == .openMenu)
        #expect(MenuBarClick(option: false, shift: true) == .openMenu)
        #expect(MenuBarClick(option: true, shift: false) == .toggleCapture)
        #expect(MenuBarClick(option: true, shift: true) == .ignoreNextCopy)
    }

    @Test("Every badge survives the helper bridge; anything else reads as no badge")
    func bridgeRoundTrip() {
        for badge in [MenuBarBadge.denied, .paused, .privateMode, .ignoreNext, .stack(3)] {
            #expect(MenuBarBadge(bridgeValue: badge.bridgeValue) == badge)
        }
        #expect(MenuBarBadge(bridgeValue: "") == nil)
        #expect(MenuBarBadge(bridgeValue: "stack:0") == nil)
        #expect(MenuBarBadge(bridgeValue: "stack:x") == nil)
    }
}
