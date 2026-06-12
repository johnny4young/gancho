#if os(macOS)
    import Foundation
    import Testing

    @testable import ClipboardCore

    /// Fixed-verdict access policy for Deny/Ask drills.
    private struct FixedAccessPolicy: PasteboardAccessPolicy {
        let verdict: PasteboardAccessVerdict
        func currentVerdict() -> PasteboardAccessVerdict { verdict }
    }

    @MainActor
    private func makeMonitor(
        pasteboard: FakePasteboard,
        activity: FakeActivity = FakeActivity(),
        verdict: PasteboardAccessVerdict = .allowed,
        preferences: CapturePreferences = CapturePreferences()
    ) -> MacPasteboardMonitor {
        MacPasteboardMonitor(
            reader: pasteboard, activity: activity,
            accessPolicy: FixedAccessPolicy(verdict: verdict),
            preferences: preferences)
    }

    @Suite("Production monitor — bursts, pause, preferences, access")
    @MainActor
    struct ProductionMonitorTests {

        @Test("A 10-copies-in-5s burst yields 10 items, in order")
        func burstOfTenInOrder() async {
            let pasteboard = FakePasteboard()
            let monitor = makeMonitor(pasteboard: pasteboard)
            var captures: [PasteboardCapture] = []
            monitor.onCapture = { captures.append($0) }

            // Real timing: one copy every ~500ms with a 250ms poll between —
            // every change is observed before the next one lands.
            for round in 0..<10 {
                pasteboard.write(.text("burst \(round)"), types: ["public.utf8-plain-text"])
                monitor.pollOnce()
                for _ in 0..<200 where captures.count < round + 1 {
                    try? await Task.sleep(for: .milliseconds(5))
                }
            }

            #expect(captures.map(\.textRepresentation) == (0..<10).map { "burst \($0)" })
        }

        @Test("Private mode pauses capture and never backfills on resume")
        func privateModeDiscardsPausedCopies() async {
            let pasteboard = FakePasteboard()
            let monitor = makeMonitor(pasteboard: pasteboard)
            var captures: [PasteboardCapture] = []
            monitor.onCapture = { captures.append($0) }

            monitor.preferences.isPrivateModePaused = true
            _ = monitor.tick()
            #expect(monitor.status == .pausedByUser)

            pasteboard.write(.text("copied in private"), types: ["public.utf8-plain-text"])
            _ = monitor.tick()
            try? await Task.sleep(for: .milliseconds(50))
            #expect(captures.isEmpty)
            #expect(pasteboard.readCalls == 0)

            monitor.preferences.isPrivateModePaused = false
            _ = monitor.tick()
            try? await Task.sleep(for: .milliseconds(100))
            #expect(captures.isEmpty, "private-mode copies must never backfill")

            pasteboard.write(.text("after private"), types: ["public.utf8-plain-text"])
            _ = monitor.tick()
            for _ in 0..<200 where captures.isEmpty {
                try? await Task.sleep(for: .milliseconds(5))
            }
            #expect(captures.map(\.textRepresentation) == ["after private"])
        }

        @Test("Screen-lock pause also discards what landed while locked")
        func lockDiscardsPausedCopies() async {
            let pasteboard = FakePasteboard()
            let activity = FakeActivity()
            let monitor = makeMonitor(pasteboard: pasteboard, activity: activity)
            var captures: [PasteboardCapture] = []
            monitor.onCapture = { captures.append($0) }

            activity.set(locked: true)
            _ = monitor.tick()
            #expect(monitor.status == .pausedByScreenLock)
            pasteboard.write(.text("while locked"), types: ["public.utf8-plain-text"])
            _ = monitor.tick()

            activity.set(locked: false)
            _ = monitor.tick()
            try? await Task.sleep(for: .milliseconds(100))
            #expect(captures.isEmpty, "locked-screen copies must never backfill")
            #expect(monitor.status == .running)
        }

        @Test("Image capture disabled skips image-only changes before reading")
        func imagesOffSkipsBeforeRead() async {
            let pasteboard = FakePasteboard()
            let monitor = makeMonitor(
                pasteboard: pasteboard,
                preferences: CapturePreferences(captureImages: false))
            var captures: [PasteboardCapture] = []
            monitor.onCapture = { captures.append($0) }

            pasteboard.write(
                .image(data: Data([1]), typeIdentifier: "public.png"), types: ["public.png"])
            monitor.pollOnce()
            try? await Task.sleep(for: .milliseconds(80))

            #expect(captures.isEmpty)
            #expect(pasteboard.readCalls == 0, "preference filter must run before the read")
        }

        @Test("Rich text disabled degrades to the plain companion")
        func richTextOffDegrades() async {
            let pasteboard = FakePasteboard()
            let monitor = makeMonitor(
                pasteboard: pasteboard,
                preferences: CapturePreferences(captureRichText: false))
            var captures: [PasteboardCapture] = []
            monitor.onCapture = { captures.append($0) }

            pasteboard.write(
                .richText(rtf: Data([0x7B]), plainText: "plain body"),
                types: ["public.rtf", "public.utf8-plain-text"])
            monitor.pollOnce()
            for _ in 0..<200 where captures.isEmpty {
                try? await Task.sleep(for: .milliseconds(5))
            }

            #expect(captures.map(\.payload) == [.text("plain body")])
        }

        @Test("Deny verdict refuses to start and surfaces the reason")
        func denyBlocksStart() {
            let pasteboard = FakePasteboard()
            let monitor = makeMonitor(pasteboard: pasteboard, verdict: .denied)

            monitor.start()
            #expect(monitor.status == .deniedByPrivacySettings)

            pasteboard.write(.text("x"), types: ["public.utf8-plain-text"])
            // No poll task is running; nothing should ever be read.
            #expect(pasteboard.readCalls == 0)
        }

        @Test("Preferences persist and reload through UserDefaults")
        func preferencesRoundTrip() throws {
            let suite = "capture-prefs-test-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }

            var prefs = CapturePreferences()
            prefs.captureImages = false
            prefs.isPrivateModePaused = true
            prefs.save(to: defaults)

            #expect(CapturePreferences.load(from: defaults) == prefs)
            // Corrupt data degrades to defaults, never crashes.
            defaults.set(Data("garbage".utf8), forKey: "capture-preferences")
            #expect(CapturePreferences.load(from: defaults) == CapturePreferences())
        }
    }
#endif
