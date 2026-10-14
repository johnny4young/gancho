import AppKit

/// A disposable receiving application. Receipts contain counts and booleans;
/// clipboard text is neither logged nor included in the receipt.
@MainActor
private final class PasteTextView: NSTextView {
    var didPaste: (() -> Void)?

    override func paste(_ sender: Any?) {
        super.paste(sender)
        didPaste?()
    }
}

@MainActor
private final class ReceiverDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let editor = PasteTextView()
    private let receipt = NSTextField(labelWithString: "pending")
    private var pasteCount = 0
    private var commandDownCount = 0
    private var commandUpCount = 0
    private var monitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["GANCHO_DISPOSABLE_PASTE_RECEIVER"] == "1",
            NSUserName() == "runner"
        else {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.regular)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let menu = NSMenu()
        let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        item.submenu = edit
        menu.addItem(item)
        NSApp.mainMenu = menu

        let window = NSWindow(
            contentRect: NSRect(x: 80, y: 80, width: 580, height: 240),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Synthetic paste receiver"
        window.setAccessibilityIdentifier("paste-receiver-window")
        editor.frame = NSRect(x: 16, y: 52, width: 548, height: 172)
        editor.isRichText = false
        editor.setAccessibilityIdentifier("paste-receiver-editor")
        editor.didPaste = { [weak self] in
            self?.pasteCount += 1
            self?.publishReceipt()
        }
        receipt.frame = NSRect(x: 16, y: 12, width: 548, height: 28)
        receipt.setAccessibilityIdentifier("paste-receipt-status")
        window.contentView?.addSubview(editor)
        window.contentView?.addSubview(receipt)
        self.window = window
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) {
            [weak self] event in
            if event.modifierFlags.contains(.command),
                event.charactersIgnoringModifiers?.lowercased() == "v"
            {
                if event.type == .keyDown { self?.commandDownCount += 1 }
                if event.type == .keyUp { self?.commandUpCount += 1 }
                self?.publishReceipt()
            }
            return event
        }
        publishReceipt()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editor)
        NSApp.activate()
    }

    private func publishReceipt() {
        let matches = editor.string == "seed beta"
        let marked =
            NSPasteboard.general.types?.contains(
                NSPasteboard.PasteboardType("com.johnny4young.gancho.self-write")) == true
        receipt.stringValue =
            "pastes=\(pasteCount);down=\(commandDownCount);up=\(commandUpCount);match=\(matches);marked=\(marked)"
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}

private let delegate = ReceiverDelegate()
private let application = NSApplication.shared
application.delegate = delegate
application.run()
