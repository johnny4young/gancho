#if os(macOS)
    import Synchronization
    import Testing

    @testable import ClipboardCore

    @Suite("Screen lock state")
    struct ScreenLockStateTests {
        private final class Session: Sendable {
            let isLocked = Mutex(false)
            let reads = Mutex(0)

            func read() -> Bool {
                reads.withLock { $0 += 1 }
                return isLocked.withLock { $0 }
            }
        }

        @Test("An unlocked answer is reused until it is due again")
        func reusesUnlocked() {
            let session = Session()
            let state = ScreenLockState(revalidateAfter: .seconds(30), readSession: session.read)
            let start = ContinuousClock.now

            #expect(!state.isLocked(now: start))
            #expect(!state.isLocked(now: start + .seconds(29)))
            #expect(session.reads.withLock { $0 } == 1)

            #expect(!state.isLocked(now: start + .seconds(30)))
            #expect(session.reads.withLock { $0 } == 2)
        }

        @Test("A locked screen is read on every call, so an unlock shows at once")
        func rereadsWhileLocked() {
            let session = Session()
            session.isLocked.withLock { $0 = true }
            let state = ScreenLockState(readSession: session.read)
            let start = ContinuousClock.now

            #expect(state.isLocked(now: start))
            session.isLocked.withLock { $0 = false }
            #expect(!state.isLocked(now: start + .seconds(2)))
            #expect(session.reads.withLock { $0 } == 2)
        }

        @Test("The lock notification drops the cached unlocked answer")
        func invalidation() {
            let session = Session()
            let state = ScreenLockState(readSession: session.read)
            let start = ContinuousClock.now
            #expect(!state.isLocked(now: start))

            session.isLocked.withLock { $0 = true }
            state.invalidate()

            #expect(state.isLocked(now: start + .seconds(1)))
        }
    }
#endif
