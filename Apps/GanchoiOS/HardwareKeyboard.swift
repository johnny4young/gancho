import GameController
import GanchoDesign
import Observation
import SwiftUI

/// Whether a hardware keyboard is attached, so the iPad shows its shortcuts
/// only to someone who can press them.
@MainActor @Observable final class HardwareKeyboard {
    /// One for the app: its observers live as long as the process does.
    static let shared = HardwareKeyboard()

    private(set) var isConnected: Bool
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    private init() {
        #if DEBUG
            let defaults = UserDefaults.standard
            if defaults.object(forKey: "ui-test-hardware-keyboard") != nil {
                isConnected = defaults.bool(forKey: "ui-test-hardware-keyboard")
                return
            }
        #endif
        isConnected = GCKeyboard.coalesced != nil
        let center = NotificationCenter.default
        for name in [Notification.Name.GCKeyboardDidConnect, .GCKeyboardDidDisconnect] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.isConnected = GCKeyboard.coalesced != nil }
                })
        }
    }
}

/// The iPad history's shortcut legend: the keys the split view binds.
struct KeyboardLegend: View {
    var body: some View {
        FlowLayout(spacing: 10) {
            entry("⌘F", Text("search"))
            entry("⌘⏎", Text("copy"))
            entry("⌘1–9", Text("copy nth"))
            entry("↑↓", Text("select"))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, GanchoTokens.Spacing.md)
        .padding(.vertical, GanchoTokens.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("history-keyboard-legend")
    }

    private func entry(_ keys: String, _ action: Text) -> some View {
        HStack(spacing: 4) {
            KeyChip(keys: keys)
            action
        }
        .fixedSize()
    }
}

/// A key combination drawn as a keycap.
struct KeyChip: View {
    let keys: String
    /// On a coloured fill the chip darkens it instead of washing it.
    var onFill = false

    var body: some View {
        Text(verbatim: keys)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(
                onFill ? Color.black.opacity(0.14) : Color.primary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 5))
    }
}
