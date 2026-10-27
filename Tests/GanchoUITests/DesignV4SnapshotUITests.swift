import AppKit
import XCTest

/// Image baselines for the surfaces the design v4 phases change. Each test
/// pins the store, tier, language, appearance and capture state so the only
/// moving part is the UI under test. Windows are rendered by the app itself
/// (`-ui-test-snapshot-dir`), so a capture never contains another app's window.
final class DesignV4SnapshotUITests: XCTestCase {
    var renders: URL!

    override func setUpWithError() throws {
        try DesignSnapshot.skipUnlessEnabled()
        continueAfterFailure = true
        renders = try DesignSnapshot.makeRenderDirectory()
    }

    override func tearDownWithError() throws {
        if let renders { try? FileManager.default.removeItem(at: renders) }
    }

    // MARK: Settings sidebar — the focus ring follows the clicked row.

    @MainActor func testSettingsSidebarAfterSelectingCaptureLight() throws {
        try settingsSidebar(appearance: "light")
    }

    @MainActor func testSettingsSidebarAfterSelectingCaptureDark() throws {
        try settingsSidebar(appearance: "dark")
    }

    @MainActor private func settingsSidebar(appearance: String) throws {
        let app = try launchSettingsWindow(extraArguments: stableArguments(appearance))
        defer { app.terminate() }
        let capture = app.windows["Settings"].buttons["settings-tab-capture"].firstMatch
        XCTAssertTrue(capture.waitForExistence(timeout: 3))
        capture.click()
        XCTAssertTrue(capture.isSelected)
        let window = try DesignSnapshot.renderWindow(
            titled: "Settings", named: "settings-\(appearance)", in: renders)
        try DesignSnapshot.save(
            DesignSnapshot.crop(window, to: CGRect(x: 0, y: 0, width: 210, height: 330)),
            named: "settings-sidebar-\(appearance)")
    }

    // MARK: Intelligence — five pipeline stages and every row icon.

    @MainActor func testIntelligenceWindowLight() throws {
        try intelligence(appearance: "light")
    }

    @MainActor func testIntelligenceWindowDark() throws {
        try intelligence(appearance: "dark")
    }

    @MainActor private func intelligence(appearance: String) throws {
        let app = try launchSettingsWindow(
            extraArguments: stableArguments(appearance) + ["-simulate-model-unavailable"])
        defer { app.terminate() }
        app.buttons["settings-tab-capture"].firstMatch.click()
        let open = app.buttons["open-intelligence"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 3))
        open.click()
        XCTAssertTrue(app.windows["Intelligence"].firstMatch.waitForExistence(timeout: 5))
        try DesignSnapshot.save(
            DesignSnapshot.renderWindow(
                titled: "Intelligence", named: "intelligence", in: renders),
            named: "intelligence-\(appearance)")
    }

    // MARK: Panel — dock states, chips, selection wash and the opaque surface.

    @MainActor func testPanelLinkPeekLight() throws {
        try panel(appearance: "light")
    }

    @MainActor func testPanelLinkPeekDark() throws {
        try panel(appearance: "dark")
    }

    /// The 11 pt chips at the two other Text size steps (9.9 and 12.65 pt).
    @MainActor func testPanelLinkPeekSmallText() throws {
        try panel(appearance: "light", textSize: "small")
    }

    @MainActor func testPanelLinkPeekLargeText() throws {
        try panel(appearance: "light", textSize: "large")
    }

    /// The wash sits behind the peek only, and the image
    /// row reads as its size and format.
    @MainActor func testPanelAmbientImageLight() throws {
        try panel(appearance: "light", ambient: true)
    }

    @MainActor func testPanelAmbientImageDark() throws {
        try panel(appearance: "dark", ambient: true)
    }

    /// The colour hero: formats, contrast cards and the colour dock.
    @MainActor func testPanelColorPeekLight() throws {
        try panel(appearance: "light", color: true)
    }

    @MainActor func testPanelColorPeekDark() throws {
        try panel(appearance: "dark", color: true)
    }

    @MainActor private func panel(
        appearance: String, textSize: String = "standard", ambient: Bool = false,
        color: Bool = false
    ) throws {
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-visual-library", "-seed-peek-link", "-force-free-tier",
            // Capturing from an empty reader, with Figma named as the paste target.
            "-force-capture-active", "-force-pasteboard-access-allowed",
            "-disable-screen-share-auto-pause", "-isolate-ui-test-system-clipboard",
            "-ui-test-paste-target", "Figma", "-ui-test-paste-sink", "pasted",
            "-opaque-panel-for-ui-test", "-place-panel-for-ui-test",
            "-suppress-storage-notice-for-ui-test", "-AppleLanguages", "(en)",
            "-appearance", appearance, "-panel-text-size", textSize,
            "-panel-ambient-tint", ambient ? "YES" : "NO",
            "-ui-test-snapshot-dir", renders.path, "-ui-test-defaults-suite",
            "com.johnny4young.gancho.uitests.snapshots.\(UUID().uuidString)"
        ]
        app.launch()
        defer { app.terminate() }
        let row = app.descendants(matching: .any).matching(identifier: "clip-row")
            .matching(
                color
                    ? NSPredicate(format: "label BEGINSWITH %@", "color,")
                    : ambient
                        ? NSPredicate(
                            format: "label BEGINSWITH %@ AND NOT (label CONTAINS %@)", "image,",
                            "•••")
                        : NSPredicate(format: "label CONTAINS %@", "example.com")
            ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["peek-dock"].firstMatch.waitForExistence(timeout: 5))
        // Let the selection and peek animations settle.
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        try DesignSnapshot.save(
            DesignSnapshot.renderWindow(titled: "Gancho", named: "panel", in: renders),
            named: color
                ? "panel-color-peek-\(appearance)"
                : ambient
                    ? "panel-ambient-image-\(appearance)"
                    : textSize == "standard"
                        ? "panel-link-peek-\(appearance)" : "panel-link-peek-\(textSize)-text")
    }

    // MARK: Panel behaviour — Private Mode, filter tokens, no results.

    @MainActor func testPanelPrivateModeLight() throws {
        try panelState(.privateMode, appearance: "light")
    }

    @MainActor func testPanelPrivateModeDark() throws {
        try panelState(.privateMode, appearance: "dark")
    }

    @MainActor func testPanelSearchTokensLight() throws {
        try panelState(.tokens, appearance: "light")
    }

    @MainActor func testPanelSearchTokensDark() throws {
        try panelState(.tokens, appearance: "dark")
    }

    @MainActor func testPanelNoResultsLight() throws {
        try panelState(.noResults, appearance: "light")
    }

    @MainActor func testPanelNoResultsDark() throws {
        try panelState(.noResults, appearance: "dark")
    }

    /// A clip dragged over a board chip: the ring and lift on the target.
    @MainActor func testPanelBoardDropTargetLight() throws {
        try panelState(.boardDropTarget, appearance: "light")
    }

    @MainActor func testPanelBoardDropTargetDark() throws {
        try panelState(.boardDropTarget, appearance: "dark")
    }

    /// A share names the app, masks the rows and offers Show anyway.
    @MainActor func testPanelScreenShareLight() throws {
        try panelState(.screenShare, appearance: "light")
    }

    @MainActor func testPanelScreenShareDark() throws {
        try panelState(.screenShare, appearance: "dark")
    }

    private enum PanelState: String {
        case privateMode = "private-mode"
        case tokens = "search-tokens"
        case noResults = "no-results"
        case screenShare = "screen-share"
        case boardDropTarget = "board-drop-target"
    }

    /// Private Mode since 14:02 today with three skipped copies and no deadline,
    /// so the banner and chip read the same on every run.
    private static var privateModePreferences: String {
        let start = Calendar.current.startOfDay(for: .now).addingTimeInterval(14 * 3600 + 120)
        let json =
            #"{"captureImages":true,"captureFileReferences":true,"captureRichText":true,"#
            + #""isPrivateModePaused":true,"privateModeStartedAt":"#
            + "\(start.timeIntervalSinceReferenceDate),"
            + #""privateModeSkippedCopies":3}"#
        return "<" + Data(json.utf8).map { String(format: "%02x", $0) }.joined() + ">"
    }

    @MainActor private func panelState(_ state: PanelState, appearance: String) throws {
        let app = GanchoUITestApplication()
        var arguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-source-apps", "-force-free-tier", "-opaque-panel-for-ui-test",
            "-place-panel-for-ui-test", "-suppress-storage-notice-for-ui-test",
            "-suppress-paused-notice-for-ui-test", "-AppleLanguages", "(en)",
            "-appearance", appearance, "-ui-test-paste-target", "Mail", "-ui-test-paste-sink",
            "pasted", "-ui-test-snapshot-dir", renders.path, "-ui-test-defaults-suite",
            "com.johnny4young.gancho.uitests.snapshots.\(UUID().uuidString)"
        ]
        switch state {
        case .privateMode: arguments += ["-capture-preferences", Self.privateModePreferences]
        case .screenShare:
            arguments += ["-simulate-screen-share", "Zoom", "-isolate-ui-test-system-clipboard"]
        case .boardDropTarget:
            arguments += [
                "-start-capture-paused", "-seed-sample-boards", "-ui-test-target-first-board"
            ]
        case .tokens, .noResults: arguments.append("-start-capture-paused")
        }
        app.launchArguments = arguments
        app.launch()
        defer { app.terminate() }
        let field = app.textFields["search-field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "clip-row").firstMatch
                .waitForExistence(timeout: 8))
        switch state {
        case .privateMode:
            break
        case .boardDropTarget:
            let chip = app.descendants(matching: .any).matching(
                NSPredicate(
                    format: "identifier BEGINSWITH 'board-' AND label BEGINSWITH %@",
                    "Seed board 1")
            ).firstMatch
            XCTAssertTrue(chip.waitForExistence(timeout: 10))
            // The pointer sits where a drag would, not on whichever row it was left over.
            try SynthesizedInput.requireForeground(app)
            chip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()
        case .screenShare:
            // Detection runs on a three-second tick.
            XCTAssertTrue(
                app.buttons["screen-share-show-anyway"].firstMatch.waitForExistence(timeout: 10))
        case .tokens:
            // Chips for app and type, then a key prefix that opens the popover.
            // Typed straight in: the field keeps only the "be" the chips leave.
            try SynthesizedInput.requireForeground(app)
            field.click()
            field.typeText("app:xcode type:code be")
        case .noResults:
            // Fuzzy finds nothing for a pattern only a regex reads.
            try typeTextReliably("sour.e", into: field, in: app)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        try DesignSnapshot.save(
            DesignSnapshot.renderWindow(titled: "Gancho", named: "panel", in: renders),
            named: "panel-\(state.rawValue)-\(appearance)")
    }

    // MARK: The empty panel teaches the three keys.

    @MainActor func testPanelFirstRunLight() throws {
        try firstRunPanel(appearance: "light")
    }

    @MainActor func testPanelFirstRunDark() throws {
        try firstRunPanel(appearance: "dark")
    }

    @MainActor private func firstRunPanel(appearance: String) throws {
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-force-free-tier", "-start-capture-paused", "-suppress-paused-notice-for-ui-test",
            "-opaque-panel-for-ui-test", "-place-panel-for-ui-test",
            "-suppress-storage-notice-for-ui-test", "-AppleLanguages", "(en)",
            "-appearance", appearance, "-ui-test-snapshot-dir", renders.path,
            // Pin the default ⇧⌘V so the baseline ignores this Mac's recorded
            // shortcut; quoted so the argument domain keeps it a string.
            "-KeyboardShortcuts_toggle-panel", #""{\"carbonKeyCode\":9,\"carbonModifiers\":768}""#,
            "-ui-test-defaults-suite",
            "com.johnny4young.gancho.uitests.snapshots.\(UUID().uuidString)"
        ]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(
            app.descendants(matching: .any)["panel-first-run-stage"].firstMatch
                .waitForExistence(timeout: 15))
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        try DesignSnapshot.save(
            DesignSnapshot.renderWindow(titled: "Gancho", named: "panel", in: renders),
            named: "panel-first-run-\(appearance)")
    }

    // MARK: Settings › Privacy and Privacy Center — neutral buttons, dark ink hero.

    @MainActor func testSettingsPrivacyLight() throws {
        try settingsPrivacy(appearance: "light")
    }

    @MainActor func testSettingsPrivacyDark() throws {
        try settingsPrivacy(appearance: "dark")
    }

    @MainActor private func settingsPrivacy(appearance: String) throws {
        let app = try launchSettingsWindow(extraArguments: stableArguments(appearance))
        defer { app.terminate() }
        let privacy = app.windows["Settings"].buttons["settings-tab-privacy"].firstMatch
        XCTAssertTrue(privacy.waitForExistence(timeout: 3))
        privacy.click()
        XCTAssertTrue(
            app.windows["Settings"].descendants(matching: .any)["spotlight-indexing-toggle"]
                .firstMatch.waitForExistence(timeout: 5))
        // Let the tab switch and the focus ring settle.
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        try DesignSnapshot.save(
            DesignSnapshot.renderWindow(titled: "Settings", named: "settings", in: renders),
            named: "settings-privacy-\(appearance)")
    }

    @MainActor func testPrivacyCenterLight() throws {
        try privacyCenter(appearance: "light")
    }

    @MainActor func testPrivacyCenterDark() throws {
        try privacyCenter(appearance: "dark")
    }

    @MainActor private func privacyCenter(appearance: String) throws {
        let token = UUID().uuidString
        let app = try launchSettingsWindow(
            extraArguments: stableArguments(appearance) + ["-command-nonce", token])
        defer { app.terminate() }
        GanchoUITestCommands.post("privacyCenter", token: token)
        XCTAssertTrue(app.windows["Privacy Center"].firstMatch.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        try DesignSnapshot.save(
            DesignSnapshot.renderWindow(
                titled: "Privacy Center", named: "privacy-center", in: renders),
            named: "privacy-center-\(appearance)")
    }

    // The status menu is not captured: it is drawn by the system with vibrancy
    // over whatever sits behind it. MenuBarShortcutUITests checks its shortcut.

    // MARK: Wrapped — the exported card carries the brand mark.

    @MainActor func testWrappedCard() throws {
        let output = renders.appendingPathComponent("wrapped.png")
        let token = UUID().uuidString
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-regular-activation-for-ui-tests", "-use-in-process-status-item",
            "-force-ephemeral-store", "-start-capture-paused", "-has-seen-welcome", "YES",
            "-AppleLanguages", "(en)", "-appearance", "light",
            "-command-nonce", token, "-ui-test-wrapped-output", output.path,
            // Pin the paste-back counter the card reads from standard defaults.
            "-first-pasteback-at", "2026-01-01", "-pasteback-count", "3"
        ]
        app.launch()
        defer { app.terminate() }
        _ = app.wait(for: .runningForeground, timeout: 8)
        GanchoUITestCommands.post("wrapped", token: token)
        let image = try XCTUnwrap(
            DesignSnapshot.waitForImage(at: output), "Wrapped PNG was not written")
        try DesignSnapshot.save(image, named: "wrapped-card")
    }

    /// Keyboard UI mode 2 is full keyboard access, so focus rings are drawn.
    func stableArguments(
        _ appearance: String, keyboardUIMode: String = "2"
    )
        -> [String]
    {
        [
            "-use-temp-durable-store", "-start-capture-paused", "-appearance", appearance,
            "-AppleKeyboardUIMode", keyboardUIMode,
            "-ui-test-defaults-suite",
            "com.johnny4young.gancho.uitests.snapshots.\(UUID().uuidString)",
            "-ui-test-snapshot-dir", renders.path, "-ui-test-privacy-overview", "128:2100000:12"
        ]
    }

    // MARK: The menu-bar hook and its badges, on a light and a dark bar.

    @MainActor func testMenuBarGlyphs() throws {
        let states: [(String, MenuBarBadge?)] = [
            ("Capturing", nil), ("Paused", .paused), ("Private", .privateMode),
            ("Denied", .denied), ("Ignore next", .ignoreNext), ("Stack", .stack(2))
        ]
        let cell = NSSize(width: 92, height: 56)
        let size = NSSize(width: cell.width * CGFloat(states.count), height: cell.height * 2)
        let bars: [(NSColor, NSColor)] = [
            (NSColor(white: 0.95, alpha: 1), .black), (NSColor(white: 0.12, alpha: 1), .white)
        ]
        let strip = NSImage(size: size, flipped: false) { _ in
            for (row, (background, ink)) in bars.enumerated() {
                let y = size.height - cell.height * CGFloat(row + 1)
                background.setFill()
                NSRect(x: 0, y: y, width: size.width, height: cell.height).fill()
                for (column, (name, badge)) in states.enumerated() {
                    let origin = NSPoint(x: cell.width * CGFloat(column), y: y)
                    let hook = MenuBarGlyph.hookImage(badged: badge != nil)
                    let hookOrigin = NSPoint(
                        x: origin.x + (cell.width - hook.size.width) / 2, y: origin.y + 24)
                    Self.tinted(hook, ink).draw(
                        at: hookOrigin, from: .zero, operation: .sourceOver, fraction: 1)
                    if let badge {
                        MenuBarGlyph.badgeImage(badge).draw(
                            at: NSPoint(
                                x: hookOrigin.x + MenuBarGlyph.badgeRect.minX,
                                y: hookOrigin.y + MenuBarGlyph.badgeRect.minY),
                            from: .zero, operation: .sourceOver, fraction: 1)
                    }
                    let label = NSAttributedString(
                        string: name,
                        attributes: [
                            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                            .foregroundColor: ink
                        ])
                    label.draw(
                        at: NSPoint(
                            x: origin.x + (cell.width - label.size().width) / 2, y: origin.y + 6))
                }
            }
            return true
        }
        let scaled = NSImage(size: NSSize(width: size.width * 3, height: size.height * 3))
        scaled.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        strip.draw(in: NSRect(origin: .zero, size: scaled.size))
        scaled.unlockFocus()
        try DesignSnapshot.save(scaled, named: "menu-bar-glyphs")
    }

    /// A template image filled with the colour the menu bar would tint it.
    private static func tinted(_ template: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: template.size, flipped: false) { rect in
            template.draw(in: rect)
            color.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}
