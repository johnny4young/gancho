#if os(macOS)
    import ClipboardCore
    import GanchoKit
    import Testing

    @testable import GanchoAppCore

    /// The paste sequence every macOS entry point shares. Every effect is a
    /// recorder: what must hold on any machine is the order the effects run in,
    /// what the reuse ledger is told, and that a clip which could not be loaded
    /// changes nothing.
    @MainActor
    @Suite("Paste-back workflow")
    struct PasteBackWorkflowTests {
        /// Every effect the workflow triggered, in order.
        private final class Log {
            var steps: [String] = []
            var pastedPlainText: Bool?
            var recordedTargets: [String?] = []
        }

        private let target = "com.example.editor"

        private func deliver(
            _ content: ClipContent?,
            answering outcome: PasteBackOutcome,
            asPlainText: Bool = false,
            into log: Log
        ) async -> PasteBackDelivery {
            let workflow = PasteBackWorkflow(
                effects: .init(
                    hidePanel: { log.steps.append("hide") },
                    waitForFocusToReturn: { log.steps.append("wait") },
                    paste: { _, plain in
                        log.steps.append("paste")
                        log.pastedPlainText = plain
                        return outcome
                    },
                    noticeCopyOnly: { log.steps.append("notice") }))
            return await workflow.deliver(
                content,
                asPlainText: asPlainText,
                intendedTarget: target,
                endInterval: { log.steps.append("end") },
                recordReuse: { confirmed in
                    log.steps.append("record")
                    log.recordedTargets.append(confirmed)
                })
        }

        @Test("A clip that could not be loaded changes nothing but closes the interval")
        func unavailableContentChangesNothing() async {
            let log = Log()
            let delivery = await deliver(nil, answering: .pasted, into: log)

            #expect(delivery == .unavailable)
            // No hidden panel, no paste, no reuse: the user stays where they were.
            #expect(log.steps == ["end"])
        }

        @Test("The panel hides and focus returns before the paste is posted")
        func panelHidesAndFocusReturnsBeforeThePaste() async {
            let log = Log()
            _ = await deliver(.text("hello"), answering: .pasted, into: log)

            #expect(log.steps == ["hide", "wait", "paste", "end", "record"])
        }

        @Test("A posted paste credits the app it was meant for")
        func postedPasteCreditsTheIntendedApp() async {
            let log = Log()
            let delivery = await deliver(.text("hello"), answering: .pasted, into: log)

            #expect(delivery == .delivered(.pasted))
            #expect(log.recordedTargets == [target])
            #expect(!log.steps.contains("notice"), "nothing to warn about after a real paste")
        }

        @Test("A copy-only paste tells the user once and credits no app")
        func copyOnlyNoticesOnceAndCreditsNoApp() async {
            let log = Log()
            let delivery = await deliver(.text("hello"), answering: .copiedOnly, into: log)

            #expect(delivery == .delivered(.copiedOnly))
            #expect(log.steps.filter { $0 == "notice" }.count == 1)
            // Nothing reached the intended app, so it must not be credited.
            #expect(log.recordedTargets == [nil])
        }

        @Test(
            "The timing interval closes once, before the reuse bookkeeping",
            arguments: [PasteBackOutcome.pasted, .copiedOnly])
        func intervalClosesOnceBeforeBookkeeping(outcome: PasteBackOutcome) async throws {
            let log = Log()
            _ = await deliver(.text("hello"), answering: outcome, into: log)

            let end = try #require(log.steps.firstIndex(of: "end"))
            let record = try #require(log.steps.firstIndex(of: "record"))
            #expect(end < record)
            #expect(log.steps.filter { $0 == "end" }.count == 1)
        }

        @Test("Plain text reaches the paste exactly as asked", arguments: [true, false])
        func plainTextPassesThrough(asPlainText: Bool) async {
            let log = Log()
            _ = await deliver(
                .text("hello"), answering: .pasted, asPlainText: asPlainText, into: log)

            #expect(log.pastedPlainText == asPlainText)
        }
    }
#endif
