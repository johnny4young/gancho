#if os(macOS)
    import Testing

    @testable import ClipboardCore

    @Suite("Release shortcut gate")
    struct ReleaseShortcutGateTests {
        private enum Step {
            case down(String)
            case up(String)
            case menu(Bool)
        }

        /// Whether each key event ran the action, in order.
        private func runs(_ steps: [Step]) -> [Bool] {
            var gate = ReleaseShortcutGate<String>()
            var decisions: [Bool] = []
            for step in steps {
                switch step {
                case .down(let name): decisions.append(gate.keyDown(name))
                case .up(let name): decisions.append(gate.keyUp(name))
                case .menu(let tracking): gate.setMenuTracking(tracking)
                }
            }
            return decisions
        }

        @Test("Outside a menu the release runs the action")
        func releaseOutsideMenus() {
            #expect(runs([.down("paste"), .up("paste")]) == [false, true])
        }

        @Test("While a menu tracks the press runs it and the release is skipped")
        func pressInsideMenus() {
            #expect(runs([.menu(true), .down("paste"), .up("paste")]) == [true, false])
        }

        @Test("A release the menu swallowed does not suppress the next press")
        func lostReleaseInsideMenus() {
            let decisions = runs([.menu(true), .down("paste"), .down("paste"), .up("paste")])
            #expect(decisions == [true, true, false])
        }

        @Test("A lost release inside a menu does not swallow the next press outside it")
        func lostReleaseThenMenuCloses() {
            let decisions = runs([
                .menu(true), .down("paste"), .menu(false), .down("paste"), .up("paste")
            ])
            #expect(decisions == [true, false, true])
        }

        @Test("A press that outlives the menu still runs once")
        func menuClosesBeforeRelease() {
            let decisions = runs([.menu(true), .down("paste"), .menu(false), .up("paste")])
            #expect(decisions == [true, false])
        }

        @Test("A press that starts before the menu opens runs on release")
        func menuOpensBeforeRelease() {
            let decisions = runs([.down("paste"), .menu(true), .up("paste")])
            #expect(decisions == [false, true])
        }

        @Test("Names are gated independently")
        func independentNames() {
            let decisions = runs([
                .menu(true), .down("paste"), .menu(false), .down("private"), .up("private"),
                .up("paste")
            ])
            #expect(decisions == [true, false, true, false])
        }
    }
#endif
