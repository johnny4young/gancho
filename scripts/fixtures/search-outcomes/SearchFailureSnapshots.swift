import AppKit
import GanchoDesign
import GanchoKit
import SwiftUI

@MainActor private final class RetryProbe { var calls = 0 }
private enum SnapshotFixtureError: Error {
    case activationPolicy
    case controlCount(Int)
    case retryCount(Int)
}

/// Captures only this view's AppKit drawing. No AppModel, app delegate, event
/// loop, global input, clipboard, capture, StoreKit or Spotlight. Containment
/// comes from absent services, not from hiding an app composition root.
@main @MainActor enum SearchFailureSnapshots {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw CocoaError(.fileWriteInvalidFileName) }
        guard NSApplication.shared.setActivationPolicy(.prohibited) else {
            throw SnapshotFixtureError.activationPolicy
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        let failures: [(String, ClipSearchError)] = [
            ("invalid-pattern", .invalidRegularExpression), ("read-failure", .readFailed)
        ]
        var controls: [[String: Any]] = []
        for language in ["en", "es"] {
            for dark in [false, true] {
                for width in [320.0, 480.0] {
                    for (name, failure) in failures {
                        let probe = RetryProbe()
                        let content = SearchFailureNotice(failure: failure) { probe.calls += 1 }
                            .environment(\.locale, Locale(identifier: language))
                            .environment(\.colorScheme, dark ? .dark : .light)
                            .frame(width: width, height: 260)
                            .background(dark ? Color(white: 0.10) : Color(white: 0.98))
                        let window = NSWindow(
                            contentRect: NSRect(x: 0, y: 0, width: width, height: 260),
                            styleMask: .borderless, backing: .buffered, defer: false)
                        window.isReleasedWhenClosed = false
                        defer { window.close() }
                        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                        let view = NSHostingView(rootView: content)
                        window.contentView = view
                        view.layoutSubtreeIfNeeded()
                        guard !window.isVisible, !window.isKeyWindow,
                            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
                        else { throw CocoaError(.fileWriteUnknown) }
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        guard let png = bitmap.representation(using: .png, properties: [:]) else {
                            throw CocoaError(.fileWriteUnknown)
                        }
                        let theme = dark ? "dark" : "light"
                        try png.write(
                            to: output.appendingPathComponent(
                                "\(language)-\(theme)-\(Int(width))-\(name).png"))
                        let nativeButtons = buttons(in: view)
                        let expected = failure == .invalidRegularExpression ? 0 : 1
                        guard nativeButtons.count == expected else {
                            throw SnapshotFixtureError.controlCount(nativeButtons.count)
                        }
                        // Sends only this owned control's target/action. No OS
                        // input synthesis, accessibility permission or window ordering.
                        nativeButtons.first?.performClick(nil)
                        guard probe.calls == expected, !window.isVisible, !window.isKeyWindow else {
                            throw SnapshotFixtureError.retryCount(probe.calls)
                        }
                        controls.append([
                            "language": language, "theme": theme, "width": width,
                            "outcome": name, "buttons": nativeButtons.count,
                            "retryCalls": probe.calls,
                            "visible": window.isVisible, "key": window.isKeyWindow
                        ])
                    }
                }
            }
        }
        try JSONSerialization.data(withJSONObject: controls, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("controls.json"))
        print(
            "Captured 16 owned component renders and local control checks; no visible/key window or iOS Simulator capture"
        )
    }

    private static func buttons(in view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
    }
}
