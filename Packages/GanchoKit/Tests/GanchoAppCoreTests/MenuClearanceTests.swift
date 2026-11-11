#if os(macOS)
    import Testing

    @testable import GanchoAppCore

    @MainActor
    @Suite("Menu clearance before a paste")
    struct MenuClearanceTests {
        private final class Log {
            var steps: [String] = []
        }

        /// The menu reports open for `openChecks` checks, then closed.
        private func clear(openChecks: Int, into log: Log) async {
            var remaining = openChecks
            let clearance = MenuClearance(
                effects: .init(
                    isMenuOpen: {
                        log.steps.append("check")
                        guard remaining > 0 else { return false }
                        remaining -= 1
                        return true
                    },
                    closeMenu: { log.steps.append("close") },
                    pause: { log.steps.append("pause") }))
            await clearance.clear()
        }

        @Test("No open menu: no close request and no wait")
        func noMenuCostsOneCheck() async {
            let log = Log()
            await clear(openChecks: 0, into: log)

            #expect(log.steps == ["check"])
        }

        @Test("An open menu is asked to close once, and the paste waits until it goes")
        func openMenuClosesBeforeThePaste() async {
            let log = Log()
            await clear(openChecks: 3, into: log)

            #expect(
                log.steps == [
                    "check", "close", "pause", "check", "pause", "check", "pause", "check"
                ])
        }

        @Test("A menu that never closes holds the paste for a bounded wait")
        func stuckMenuStopsWaiting() async {
            let log = Log()
            await clear(openChecks: .max, into: log)

            #expect(log.steps.filter { $0 == "close" }.count == 1)
            #expect(log.steps.filter { $0 == "pause" }.count == MenuClearance.maximumChecks)
            #expect(log.steps.last == "check")
        }
    }
#endif
