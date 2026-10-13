import AppKit
import XCTest

final class ShortcutRecorderUITests: XCTestCase {
    @MainActor
    func testStoredShortcutsRestoreAndDispatchOnce() async throws {
        let configuration = try RecorderConfiguration()
        let app = XCUIApplication(bundleIdentifier: configuration.bundleIdentifier)
        defer { cleanUp(app, configuration: configuration) }
        let initial = try await launch(app, configuration: configuration, seed: true)

        try typeKey("v", in: app, configuration: configuration, modifiers: allModifiers)
        _ = try await waitForSnapshot(configuration) { $0.panelDown == 1 && $0.panelUp == 1 }
        try typeKey("k", in: app, configuration: configuration, modifiers: allModifiers)
        let delivered = try await waitForSnapshot(configuration) {
            $0.cyclicDown == 1 && $0.cyclicUp == 1
        }
        try await observeCounters(configuration, panel: 1, cyclic: 1)
        XCTAssertEqual(delivered.storedValues, initial.seededValues)
        XCTAssertEqual(delivered.changes, 0)
        try attach(delivered, name: "restored-recorder-bindings-delivered-once")
    }

    @MainActor
    func testCancelSwitchAndOutsideClickPreserveBindings() async throws {
        let configuration = try RecorderConfiguration()
        let app = XCUIApplication(bundleIdentifier: configuration.bundleIdentifier)
        defer { cleanUp(app, configuration: configuration) }
        let initial = try await launch(app, configuration: configuration, seed: true)

        try await beginRecording("panel-shortcut-recorder", in: app, configuration: configuration)
        try typeKey(
            XCUIKeyboardKey.escape.rawValue, in: app, configuration: configuration,
            recorder: "panel-shortcut-recorder")
        let cancelled = try await waitForSnapshot(configuration) { !$0.recordingActive }
        try require(
            cancelled.storedValues == initial.seededValues,
            "Escape changed a persisted shortcut before the next recording gesture")

        try await beginRecording("panel-shortcut-recorder", in: app, configuration: configuration)
        try await beginRecording("cyclic-shortcut-recorder", in: app, configuration: configuration)
        try typeKey(
            XCUIKeyboardKey.escape.rawValue, in: app, configuration: configuration,
            recorder: "cyclic-shortcut-recorder")
        let switched = try await waitForSnapshot(configuration) { !$0.recordingActive }
        try require(
            switched.storedValues == initial.seededValues,
            "Switching recorders changed a persisted shortcut")

        try await beginRecording("panel-shortcut-recorder", in: app, configuration: configuration)
        try click(app.buttons["stop-recording-button"], in: app, configuration: configuration)
        let stopped = try await waitForSnapshot(configuration) { !$0.recordingActive }
        try require(
            stopped.storedValues == initial.seededValues && stopped.changes == 0,
            "Cancelling recording changed the binding before dispatch resumed")
        try await observeCounters(configuration, panel: 0, cyclic: 0)

        try typeKey("v", in: app, configuration: configuration, modifiers: allModifiers)
        let resumed = try await waitForSnapshot(configuration) {
            $0.panelDown == 1 && $0.panelUp == 1
        }
        try await observeCounters(configuration, panel: 1, cyclic: 0)
        try attach(resumed, name: "cancelled-recorders-preserved-bindings-and-resumed")
    }

    @MainActor
    func testRerecordOwnBindingAvoidsConflictAndRecordingCallbacks() async throws {
        let configuration = try RecorderConfiguration()
        let app = XCUIApplication(bundleIdentifier: configuration.bundleIdentifier)
        defer { cleanUp(app, configuration: configuration) }
        let initial = try await launch(app, configuration: configuration, seed: true)
        try require(
            initial.boundMenuKey == "v" && initial.boundMenuModifiers == 1_966_080,
            "The own-binding menu prerequisite was not established before re-recording")

        try await beginRecording("panel-shortcut-recorder", in: app, configuration: configuration)
        try typeKey(
            "v", in: app, configuration: configuration, modifiers: allModifiers,
            recorder: "panel-shortcut-recorder")
        let recorded = try await waitForSnapshot(configuration) {
            !$0.recordingActive && $0.changes == 1
        }
        try require(
            !app.sheets.firstMatch.exists && !app.dialogs.firstMatch.exists,
            "Re-recording the own binding opened an unexpected conflict alert")
        try require(
            try preferences(recorded.storedValues) == preferences(initial.seededValues),
            "Re-recording the own binding changed its persisted meaning")
        try await observeCounters(configuration, panel: 0, cyclic: 0)

        try typeKey("v", in: app, configuration: configuration, modifiers: allModifiers)
        let resumed = try await waitForSnapshot(configuration) {
            $0.panelDown == 1 && $0.panelUp == 1
        }
        try await observeCounters(configuration, panel: 1, cyclic: 0)
        try attach(resumed, name: "own-binding-rerecorded-without-action-or-conflict")
    }

    @MainActor
    func testReplacementDeactivatesOldBindingAndSurvivesRelaunch() async throws {
        let configuration = try RecorderConfiguration()
        let app = XCUIApplication(bundleIdentifier: configuration.bundleIdentifier)
        defer { cleanUp(app, configuration: configuration) }
        let initial = try await launch(app, configuration: configuration, seed: true)

        try await beginRecording("panel-shortcut-recorder", in: app, configuration: configuration)
        try typeKey(
            "u", in: app, configuration: configuration, modifiers: allModifiers,
            recorder: "panel-shortcut-recorder")
        let replacement = try await waitForSnapshot(configuration) {
            !$0.recordingActive && $0.changes == 1 && $0.panelKeyCode == 32
                && $0.boundMenuKey == "u"
        }
        try requirePanel(replacement, keyCode: 32, key: "U")
        var expected = try preferences(initial.seededValues)
        expected["KeyboardShortcuts_toggle-panel"] = .shortcut(keyCode: 32, modifiers: 6912)
        try require(
            try preferences(replacement.storedValues) == expected,
            "Recording a replacement changed another shortcut")
        try await observeCounters(configuration, panel: 0, cyclic: 0)

        try typeKey("v", in: app, configuration: configuration, modifiers: allModifiers)
        try await observeCounters(configuration, panel: 0, cyclic: 0)
        try typeKey("u", in: app, configuration: configuration, modifiers: allModifiers)
        _ = try await waitForSnapshot(configuration) { $0.panelDown == 1 && $0.panelUp == 1 }
        try await observeCounters(configuration, panel: 1, cyclic: 0)

        app.terminate()
        let restored = try await launch(app, configuration: configuration, seed: false)
        try require(
            restored.storedValues == replacement.storedValues,
            "The replacement binding changed during a real relaunch")
        try requirePanel(restored, keyCode: 32, key: "U")
        try typeKey("u", in: app, configuration: configuration, modifiers: allModifiers)
        let delivered = try await waitForSnapshot(configuration) {
            $0.panelDown == 1 && $0.panelUp == 1
        }
        try await observeCounters(configuration, panel: 1, cyclic: 0)
        XCTAssertEqual(delivered.storedValues, replacement.storedValues)
        try attach(delivered, name: "replacement-binding-restored-after-real-relaunch")
    }

    @MainActor
    func testConflictPreservesBindingAndNativeClearSurvivesRelaunch() async throws {
        let configuration = try RecorderConfiguration()
        let app = XCUIApplication(bundleIdentifier: configuration.bundleIdentifier)
        defer { cleanUp(app, configuration: configuration) }
        let initial = try await launch(app, configuration: configuration, seed: true)

        try await beginRecording("panel-shortcut-recorder", in: app, configuration: configuration)
        try typeKey(
            "j", in: app, configuration: configuration, modifiers: .command,
            recorder: "panel-shortcut-recorder")
        let dismiss = app.buttons["OK"].firstMatch
        try await waitForElement(dismiss)
        let blocked = try readSnapshot(configuration)
        try require(
            blocked.storedValues == initial.seededValues && blocked.changes == 0,
            "The menu conflict changed a persisted binding before alert dismissal")
        try click(dismiss, in: app, configuration: configuration)
        try await waitForRecordingFocus(
            "panel-shortcut-recorder", in: app,
            configuration: configuration)
        try typeKey(
            XCUIKeyboardKey.escape.rawValue, in: app, configuration: configuration,
            recorder: "panel-shortcut-recorder")
        let rejected = try await waitForSnapshot(configuration) { !$0.recordingActive }
        try require(
            rejected.storedValues == initial.seededValues && rejected.changes == 0,
            "Rejecting the menu conflict changed a persisted binding")
        try requirePanel(rejected, keyCode: 9, key: "V")
        try typeKey("v", in: app, configuration: configuration, modifiers: allModifiers)
        _ = try await waitForSnapshot(configuration) { $0.panelDown == 1 && $0.panelUp == 1 }

        try await beginRecording("cyclic-shortcut-recorder", in: app, configuration: configuration)
        try typeKey(
            XCUIKeyboardKey.delete.rawValue, in: app, configuration: configuration,
            recorder: "cyclic-shortcut-recorder")
        _ = try await waitForSnapshot(configuration) {
            $0.cyclicKeyCode == -1 && $0.cyclicModifiers == -1 && !$0.cyclicEnabled
        }
        try click(app.buttons["stop-recording-button"], in: app, configuration: configuration)
        let cleared = try await waitForSnapshot(configuration) { !$0.recordingActive }
        var expected = try preferences(initial.seededValues)
        expected.removeValue(forKey: "KeyboardShortcuts_cyclic-paste")
        try require(
            try preferences(cleared.storedValues) == expected,
            "Native clear changed a shortcut other than the optional cyclic binding")
        try requireCyclicCleared(cleared)
        try typeKey("k", in: app, configuration: configuration, modifiers: allModifiers)
        try await observeCounters(configuration, panel: 1, cyclic: 0)

        app.terminate()
        let restored = try await launch(app, configuration: configuration, seed: false)
        try require(
            restored.storedValues == cleared.storedValues,
            "The cleared optional binding changed during a real relaunch")
        try requireCyclicCleared(restored)
        try typeKey("k", in: app, configuration: configuration, modifiers: allModifiers)
        try await observeCounters(configuration, panel: 0, cyclic: 0)
        try attach(restored, name: "menu-conflict-rejected-and-optional-binding-cleared")
    }
}

extension ShortcutRecorderUITests {
    private var allModifiers: XCUIElement.KeyModifierFlags {
        [.command, .control, .option, .shift]
    }

    @MainActor
    private func launch(
        _ app: XCUIApplication, configuration: RecorderConfiguration, seed: Bool
    ) async throws -> RecorderSnapshot {
        app.launchArguments =
            [
                "-fixture-snapshot", configuration.snapshotURL.path, "-AppleLanguages", "(en)"
            ] + (seed ? ["-fixture-seed"] : [])
        app.launch()
        try await waitForElement(app.windows["Shortcut Recorder Fixture"], seconds: 8)
        app.activate()
        for _ in 0..<100 {
            if app.state == .runningForeground,
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                    == configuration.bundleIdentifier
            {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        try requireForeground(app, configuration: configuration)
        let initial = try await waitForSnapshot(configuration) {
            $0.recordersReady && !$0.recordingActive && !$0.panelDisplay.isEmpty
                && (!seed || !$0.cyclicDisplay.isEmpty)
                && $0.changes == 0 && $0.panelDown == 0 && $0.panelUp == 0
                && $0.cyclicDown == 0 && $0.cyclicUp == 0
        }
        if seed {
            try require(
                initial.storedValues == initial.seededValues,
                "The initial names rewrote the raw seeded preferences")
            try requirePanel(initial, keyCode: 9, key: "V")
            try require(
                initial.cyclicKeyCode == 40 && initial.cyclicModifiers == 6912
                    && initial.cyclicEnabled,
                "The optional cyclic binding did not restore and register")
            try requireDisplay(initial.cyclicDisplay, key: "K")
        }
        return initial
    }

    @MainActor
    private func cleanUp(_ app: XCUIApplication, configuration: RecorderConfiguration) {
        app.terminate()
        // Configuration validates the complete UUID fixture identity before cleanup.
        UserDefaults.standard.removePersistentDomain(forName: configuration.bundleIdentifier)
    }

    @MainActor
    private func requireForeground(
        _ app: XCUIApplication, configuration: RecorderConfiguration
    ) throws {
        let state = app.state
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "missing"
        let mainWindow = app.windows["Shortcut Recorder Fixture"].exists
        let dialog = app.dialogs.firstMatch.exists
        let sheet = app.sheets.firstMatch.exists
        // A modal native alert can hide its owning main window from AX. A
        // dialog/sheet must belong to this XCUIApplication, while both process
        // ownership checks remain mandatory before any input.
        guard state == .runningForeground, frontmost == configuration.bundleIdentifier,
            mainWindow || dialog || sheet
        else {
            attachFailureSnapshot(configuration, name: "recorder-foreground-failure")
            throw fixtureError(
                "Fixture foreground guard failed: appState=\(state), frontmostUUID=\(frontmost), "
                    + "expectedUUID=\(configuration.bundleIdentifier), mainWindow=\(mainWindow), "
                    + "dialog=\(dialog), sheet=\(sheet)")
        }
    }

    @MainActor
    private func click(
        _ element: XCUIElement, in app: XCUIApplication, configuration: RecorderConfiguration
    ) throws {
        try require(
            readSnapshot(configuration).recordersReady,
            "The native recorder views are not ready before fixture input")
        guard element.exists, element.isHittable, !element.frame.isEmpty, !element.frame.isInfinite
        else { throw fixtureError("The recorder fixture click target is missing or not hittable") }
        try requireForeground(app, configuration: configuration)
        element.click()
    }

    @MainActor
    private func typeKey(
        _ key: String, in app: XCUIApplication, configuration: RecorderConfiguration,
        modifiers: XCUIElement.KeyModifierFlags = [], recorder: String? = nil
    ) throws {
        let snapshot = try readSnapshot(configuration)
        try require(
            snapshot.recordersReady,
            "The native recorder views are not ready before fixture input")
        if let recorder {
            let field = app.searchFields[recorder].firstMatch
            guard snapshot.recordingActive, field.exists, field.isHittable,
                (field.value(forKey: "hasKeyboardFocus") as? Bool) == true
            else { throw fixtureError("The intended native recorder does not hold keyboard focus") }
        } else {
            guard !snapshot.recordingActive else {
                throw fixtureError("The fixture is still recording before shortcut dispatch")
            }
        }
        // XCUITest keys are global. A focus change after this check remains a host race.
        try requireForeground(app, configuration: configuration)
        app.typeKey(key, modifierFlags: modifiers)
    }

    @MainActor
    private func beginRecording(
        _ identifier: String, in app: XCUIApplication, configuration: RecorderConfiguration
    ) async throws {
        let recorder = app.searchFields[identifier].firstMatch
        try await waitForElement(recorder)
        try click(recorder, in: app, configuration: configuration)
        try await waitForRecordingFocus(identifier, in: app, configuration: configuration)
    }

    @MainActor
    private func waitForRecordingFocus(
        _ identifier: String, in app: XCUIApplication, configuration: RecorderConfiguration
    ) async throws {
        let recorder = app.searchFields[identifier].firstMatch
        for _ in 0..<100 {
            if try readSnapshot(configuration).recordingActive,
                recorder.exists, (recorder.value(forKey: "hasKeyboardFocus") as? Bool) == true
            {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        attachFailureSnapshot(configuration, name: "recorder-focus-timeout")
        let exists = recorder.exists
        let focused = exists && (recorder.value(forKey: "hasKeyboardFocus") as? Bool) == true
        throw fixtureError(
            "Native recorder focus timed out: recorder=\(identifier), exists=\(exists), "
                + "hasKeyboardFocus=\(focused)")
    }

    @MainActor
    private func waitForElement(_ element: XCUIElement, seconds: Int = 5) async throws {
        for _ in 0..<(seconds * 20) {
            if element.exists, element.isHittable { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw fixtureError("The expected recorder fixture element did not become hittable")
    }

    @MainActor
    private func waitForSnapshot(
        _ configuration: RecorderConfiguration, matching predicate: (RecorderSnapshot) -> Bool
    ) async throws -> RecorderSnapshot {
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: configuration.snapshotURL.path) {
                let snapshot = try readSnapshot(configuration)
                if predicate(snapshot) { return snapshot }
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        attachFailureSnapshot(configuration, name: "recorder-state-timeout")
        throw fixtureError("The recorder fixture snapshot did not reach the expected state")
    }

    @MainActor
    private func observeCounters(
        _ configuration: RecorderConfiguration, panel: Int, cyclic: Int
    ) async throws {
        for _ in 0..<10 {
            let snapshot = try readSnapshot(configuration)
            guard snapshot.panelDown == panel, snapshot.panelUp == panel,
                snapshot.cyclicDown == cyclic, snapshot.cyclicUp == cyclic
            else {
                attachFailureSnapshot(configuration, name: "recorder-callback-failure")
                throw fixtureError("A native shortcut callback was missing, duplicated, or leaked")
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private func readSnapshot(_ configuration: RecorderConfiguration) throws -> RecorderSnapshot {
        let snapshot = try JSONDecoder().decode(
            RecorderSnapshot.self, from: Data(contentsOf: configuration.snapshotURL))
        guard snapshot.bundleIdentifier == configuration.bundleIdentifier,
            snapshot.version == configuration.version, snapshot.revision == configuration.revision
        else { throw fixtureError("The recorder snapshot has a different identity or dependency") }
        return snapshot
    }

    private func require(_ condition: Bool, _ description: String) throws {
        guard condition else { throw fixtureError(description) }
    }

    private func requirePanel(_ snapshot: RecorderSnapshot, keyCode: Int, key: String) throws {
        try require(
            snapshot.panelKeyCode == keyCode && snapshot.panelModifiers == 6912
                && snapshot.panelEnabled && snapshot.boundMenuKey == key.lowercased()
                && snapshot.boundMenuModifiers == 1_966_080,
            "The expected panel binding, registration, and menu binding are not established")
        try requireDisplay(snapshot.panelDisplay, key: key)
    }

    private func requireCyclicCleared(_ snapshot: RecorderSnapshot) throws {
        try require(
            snapshot.cyclicKeyCode == -1 && snapshot.cyclicModifiers == -1
                && !snapshot.cyclicEnabled && snapshot.cyclicDisplay.isEmpty,
            "The cleared cyclic binding is still stored, registered, or displayed")
    }

    private func requireDisplay(_ display: String, key: String) throws {
        try require(
            display.uppercased().hasSuffix(key)
                && ["⌃", "⌥", "⇧", "⌘"].allSatisfy { display.contains($0) },
            "The native recorder does not display the expected key and every modifier")
    }

    private func preferences(_ encoded: String) throws -> [String: RecorderPreference] {
        let values = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any])
        var decoded: [String: RecorderPreference] = [:]
        for (key, value) in values {
            guard key.hasPrefix("KeyboardShortcuts_") else {
                throw fixtureError("The fixture snapshot contains a non-shortcut preference")
            }
            if let shortcut = value as? String {
                let fields = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: Data(shortcut.utf8)) as? [String: Int])
                decoded[key] = .shortcut(
                    keyCode: try XCTUnwrap(fields["carbonKeyCode"]),
                    modifiers: try XCTUnwrap(fields["carbonModifiers"]))
            } else if value as? Bool == false {
                decoded[key] = .disabled
            } else {
                throw fixtureError("The fixture contains an unsupported shortcut storage value")
            }
        }
        return decoded
    }

    private func attach(_ snapshot: RecorderSnapshot, name: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let attachment = XCTAttachment(
            data: try encoder.encode(snapshot), uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachFailureSnapshot(_ configuration: RecorderConfiguration, name: String) {
        do {
            try attach(readSnapshot(configuration), name: name)
        } catch {
            let attachment = XCTAttachment(
                string: "Synthetic recorder failure snapshot unavailable: \(error)")
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}

private struct RecorderConfiguration: Sendable {
    let bundleIdentifier: String
    let snapshotURL: URL
    let version: String
    let revision: String

    init() throws {
        let environment = ProcessInfo.processInfo.environment
        bundleIdentifier = try XCTUnwrap(environment["SHORTCUT_RECORDER_BUNDLE_ID"])
        snapshotURL =
            URL(fileURLWithPath: try XCTUnwrap(environment["SHORTCUT_RECORDER_SNAPSHOT"]))
            .standardizedFileURL
        version = try XCTUnwrap(environment["SHORTCUT_MENU_VERSION"])
        revision = try XCTUnwrap(environment["SHORTCUT_MENU_REVISION"])
        let domainPattern =
            "^com\\.johnny4young\\.gancho\\.tests\\.shortcut-recorder\\.[0-9a-f]{32}$"
        let directory = snapshotURL.deletingLastPathComponent().lastPathComponent
        guard bundleIdentifier.range(of: domainPattern, options: .regularExpression) != nil,
            snapshotURL.pathExtension == "json",
            directory.hasPrefix("gancho-shortcut-menu.")
                || directory.hasPrefix("gancho-shortcut-recorder."),
            version.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil,
            revision.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil
        else {
            throw fixtureError("The recorder fixture configuration is not isolated and canonical")
        }
    }
}

private struct RecorderSnapshot: Codable, Sendable {
    let bundleIdentifier: String
    let version: String
    let revision: String
    let seededValues: String
    let storedValues: String
    let panelDown: Int
    let panelUp: Int
    let cyclicDown: Int
    let cyclicUp: Int
    let changes: Int
    let recordersReady: Bool
    let recordingActive: Bool
    let panelKeyCode: Int
    let panelModifiers: Int
    let cyclicKeyCode: Int
    let cyclicModifiers: Int
    let panelEnabled: Bool
    let cyclicEnabled: Bool
    let boundMenuKey: String
    let boundMenuModifiers: Int
    let panelDisplay: String
    let cyclicDisplay: String
}

private enum RecorderPreference: Equatable, Sendable {
    case shortcut(keyCode: Int, modifiers: Int)
    case disabled
}

private func fixtureError(_ description: String) -> NSError {
    NSError(
        domain: "ShortcutRecorderFixture", code: 1,
        userInfo: [NSLocalizedDescriptionKey: description])
}
