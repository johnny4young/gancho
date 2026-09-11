#if os(macOS)
    import ClipboardCore
    import Testing

    @testable import GanchoAppCore

    /// The one decision about what a Mac launch opens. Pure, so the ordering
    /// between onboarding, the pasteboard explainer and the UI-test panel hook
    /// is pinned without launching an app.
    @Suite("Launch presentation")
    struct LaunchPresentationTests {
        private func decide(
            opensPanel: Bool = false,
            forcesWelcome: Bool = false,
            hasSeenWelcome: Bool = true,
            monitorStatus: MonitorStatus = .running
        ) -> LaunchPresentation {
            LaunchPresentation.decide(
                opensPanel: opensPanel, forcesWelcome: forcesWelcome,
                hasSeenWelcome: hasSeenWelcome, monitorStatus: monitorStatus)
        }

        @Test("A first run introduces itself")
        func firstRunShowsWelcome() {
            #expect(decide(hasSeenWelcome: false) == .welcome)
        }

        @Test("Onboarding outranks the pasteboard explainer on a first run")
        func welcomeOutranksThePasteboardExplainer() {
            // Being asked to change a system privacy setting before the app has
            // introduced itself is the wrong first impression; the explainer is
            // still there on the next launch.
            #expect(
                decide(hasSeenWelcome: false, monitorStatus: .deniedByPrivacySettings) == .welcome)
        }

        @Test("A returning user on a Mac that refuses pasteboard reads gets the explainer")
        func deniedPasteboardShowsTheExplainer() {
            #expect(decide(monitorStatus: .deniedByPrivacySettings) == .pasteboardPermission)
        }

        @Test(
            "Every other monitor state opens nothing",
            arguments: [
                MonitorStatus.stopped, .running, .pausedByUser, .pausedByScreenLock,
                .pausedByScreenShare
            ])
        func returningUserOpensNothing(status: MonitorStatus) {
            #expect(decide(monitorStatus: status) == .menuBarOnly)
        }

        @Test("The panel hook outranks both windows", arguments: [false, true])
        func panelHookOutranksTheWindows(hasSeenWelcome: Bool) {
            #expect(
                decide(
                    opensPanel: true, forcesWelcome: true, hasSeenWelcome: hasSeenWelcome,
                    monitorStatus: .deniedByPrivacySettings) == .panel)
        }

        @Test("The welcome hook reopens onboarding for a returning user")
        func forcedWelcomeReopensOnboarding() {
            #expect(decide(forcesWelcome: true) == .welcome)
        }
    }
#endif
