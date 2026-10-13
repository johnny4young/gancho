import AppKit
import KeyboardShortcuts
import SwiftUI

/// Allow the native recorder to receive already registered shortcuts.
struct ShortcutRecorder: View {
    private let title: LocalizedStringKey
    private let name: KeyboardShortcuts.Name
    private let conflictPolicy: KeyboardShortcuts.ConflictPolicy
    private let accessibilityIdentifier: String?
    private let onChange: ((KeyboardShortcuts.Shortcut?) -> Void)?

    init(
        _ title: LocalizedStringKey,
        name: KeyboardShortcuts.Name,
        conflictPolicy: KeyboardShortcuts.ConflictPolicy = .default,
        accessibilityIdentifier: String? = nil,
        onChange: ((KeyboardShortcuts.Shortcut?) -> Void)? = nil
    ) {
        self.title = title
        self.name = name
        self.conflictPolicy = conflictPolicy
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onChange = onChange
    }

    var body: some View {
        LabeledContent(title) {
            NativeShortcutRecorder(
                name: name, conflictPolicy: conflictPolicy,
                accessibilityIdentifier: accessibilityIdentifier, onChange: onChange)
        }
    }
}

private struct NativeShortcutRecorder: NSViewRepresentable {
    let name: KeyboardShortcuts.Name
    let conflictPolicy: KeyboardShortcuts.ConflictPolicy
    let accessibilityIdentifier: String?
    let onChange: ((KeyboardShortcuts.Shortcut?) -> Void)?

    final class Coordinator {
        var onChange: ((KeyboardShortcuts.Shortcut?) -> Void)?

        init(onChange: ((KeyboardShortcuts.Shortcut?) -> Void)?) {
            self.onChange = onChange
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> ShortcutRecorderHostView {
        let coordinator = context.coordinator
        let recorder = KeyboardShortcuts.RecorderCocoa(for: name) { [weak coordinator] shortcut in
            coordinator?.onChange?(shortcut)
        }
        recorder.conflictPolicy = conflictPolicy
        recorder.setAccessibilityIdentifier(accessibilityIdentifier)
        return ShortcutRecorderHostView(recorder: recorder)
    }

    func updateNSView(_ host: ShortcutRecorderHostView, context: Context) {
        context.coordinator.onChange = onChange
        host.recorder.shortcutName = name
        host.recorder.conflictPolicy = conflictPolicy
        host.recorder.setAccessibilityIdentifier(accessibilityIdentifier)
    }

    static func dismantleNSView(_ host: ShortcutRecorderHostView, coordinator: Coordinator) {
        host.tearDown()
        coordinator.onChange = nil
    }
}

/// The global switch suspends Carbon registration without changing stored
/// shortcuts, handlers, or the dependency's per-name enabled flags.
@MainActor
private final class ShortcutRecordingSuspension {
    static let shared = ShortcutRecordingSuspension()
    private var owners: Set<ObjectIdentifier> = []
    private var previousEnabled: Bool?

    func acquire(_ owner: AnyObject) {
        guard owners.insert(ObjectIdentifier(owner)).inserted else { return }
        guard owners.count == 1 else { return }
        previousEnabled = KeyboardShortcuts.isEnabled
        KeyboardShortcuts.isEnabled = false
    }

    func release(_ owner: AnyObject) {
        guard owners.remove(ObjectIdentifier(owner)) != nil,
            owners.isEmpty, let previousEnabled
        else { return }
        self.previousEnabled = nil
        KeyboardShortcuts.isEnabled = previousEnabled
    }
}

@MainActor
private final class ShortcutRecorderHostView: NSView {
    let recorder: KeyboardShortcuts.RecorderCocoa
    private weak var observedWindow: NSWindow?
    private var firstResponderObservation: NSKeyValueObservation?
    private var windowObservers: [NSObjectProtocol] = []
    private var isWindowActive = false
    private var isTornDown = false

    init(recorder: KeyboardShortcuts.RecorderCocoa) {
        self.recorder = recorder
        super.init(frame: recorder.frame)
        setAccessibilityElement(false)
        setContentHuggingPriority(
            recorder.contentHuggingPriority(for: .horizontal), for: .horizontal)
        setContentHuggingPriority(recorder.contentHuggingPriority(for: .vertical), for: .vertical)
        recorder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(recorder)
        NSLayoutConstraint.activate([
            recorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            recorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            recorder.topAnchor.constraint(equalTo: topAnchor),
            recorder.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ShortcutRecorderHostView requires a native recorder")
    }

    isolated deinit { stopObservingWindow() }

    override var intrinsicContentSize: NSSize { recorder.intrinsicContentSize }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !isTornDown, window !== observedWindow else { return }
        stopObservingWindow()
        guard let window else { return }
        observedWindow = window
        isWindowActive = window.isKeyWindow

        // NSWindow explicitly supports KVO for firstResponder. Observe focus
        // synchronously: text-editing notifications can arrive after input.
        firstResponderObservation = window.observe(
            \.firstResponder, options: [.initial, .new]
        ) { [weak self] window, _ in
            self?.reconcileOnMainThread(in: window)
        }
        for name in [
            NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
            NSWindow.willCloseNotification, NSWindow.didUpdateNotification
        ] {
            let observer = NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main
            ) { [weak self, weak window] notification in
                guard let window else { return }
                self?.reconcileOnMainThread(in: window, notification: notification.name)
            }
            windowObservers.append(observer)
        }
    }

    func tearDown() {
        guard !isTornDown else { return }
        isTornDown = true
        if let window = observedWindow, recorderHasFocus(in: window) {
            window.makeFirstResponder(nil)
        }
        stopObservingWindow()
    }

    nonisolated private func reconcileOnMainThread(
        in window: NSWindow, notification: Notification.Name? = nil
    ) {
        precondition(Thread.isMainThread, "Native recorder focus must change on the main thread")
        MainActor.assumeIsolated { [weak self] in
            guard let self, !isTornDown, window === observedWindow else { return }
            if notification == NSWindow.didBecomeKeyNotification {
                isWindowActive = true
            } else if notification == NSWindow.didResignKeyNotification
                || notification == NSWindow.willCloseNotification
            {
                isWindowActive = false
            }
            if isWindowActive, window.isKeyWindow, recorderHasFocus(in: window) {
                ShortcutRecordingSuspension.shared.acquire(self)
            } else {
                ShortcutRecordingSuspension.shared.release(self)
            }
        }
    }

    private func recorderHasFocus(in window: NSWindow) -> Bool {
        guard recorder.window === window else { return false }
        let responder = window.firstResponder
        if responder === recorder { return true }
        // AppKit reuses a window's field editor when switching controls. The
        // window update notification also reconciles that unchanged responder.
        guard let editor = responder as? NSTextView, editor.isFieldEditor else { return false }
        // AppKit installs the editor in the control before assigning its
        // delegate/currentEditor association. Recognize that early ownership.
        if editor.isDescendant(of: recorder) { return true }
        return recorder.currentEditor() === editor && editor.delegate === recorder
    }

    private func stopObservingWindow() {
        firstResponderObservation?.invalidate()
        firstResponderObservation = nil
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers.removeAll()
        observedWindow = nil
        isWindowActive = false
        ShortcutRecordingSuspension.shared.release(self)
    }
}
