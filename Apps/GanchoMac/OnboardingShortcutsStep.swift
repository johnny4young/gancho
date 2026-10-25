import ClipboardCore
import GanchoAppCore
import GanchoDesign
import KeyboardShortcuts
import SwiftUI

/// Step 3: the three global shortcuts as configured, each editable in place.
/// An unset one says so; nothing gets a default it never had.
struct OnboardingShortcutsStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            OnboardingStepHeader(
                title: "Your clipboard, one shortcut away",
                message: Text(
                    // swiftlint:disable:next line_length
                    "Press the shortcut, pick a clip with ↑↓, hit Enter — it pastes right where you were typing. That’s the whole loop."
                )
            ) {
                Image(systemName: "keyboard")
                    .font(.system(size: 30))
                    .foregroundStyle(GanchoTokens.Palette.accentInk)
            }
            VStack(spacing: 6) {
                OnboardingShortcutRow(
                    title: "Open Gancho panel", name: .togglePanel, id: "panel")
                OnboardingShortcutRow(
                    title: "Paste from stack", name: .pasteFromStack, id: "stack")
                OnboardingShortcutRow(
                    title: "Private mode", name: .togglePrivateMode, id: "private-mode")
            }
            .padding(.top, 2)
            Text("Forgot it? Gancho also lives in your menu bar — click the hook anytime.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
    }
}

private struct OnboardingShortcutRow: View {
    let title: LocalizedStringKey
    let name: KeyboardShortcuts.Name
    let id: String
    @State private var shortcut: KeyboardShortcuts.Shortcut?
    @State private var isEditing = false
    @State private var conflict: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(title)
                Spacer(minLength: 0)
                if isEditing {
                    ShortcutRecorder(
                        "", name: name,
                        accessibilityIdentifier: "onboarding-shortcut-recorder-\(id)"
                    ) { recorded in
                        shortcut = recorded
                        conflict = recorded.flatMap { ShortcutConflicts.conflict(with: "\($0)") }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button("Done") { isEditing = false }
                        .ganchoTextButton()
                        .accessibilityIdentifier("onboarding-shortcut-done-\(id)")
                } else {
                    keycaps
                    Button(shortcut == nil ? "Set…" : "Change…") { isEditing = true }
                        .ganchoTextButton()
                        .font(.system(size: 11.5, weight: .bold))
                        .accessibilityIdentifier("onboarding-shortcut-change-\(id)")
                }
            }
            if let conflict {
                Label(
                    "This shortcut is used by the system (\(conflict)).",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 11))
                .foregroundStyle(GanchoTokens.Palette.warningInk)
            }
        }
        .font(.system(size: 12))
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(minHeight: 36)
        .background(.background, in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: GanchoTokens.Radius.md)
                .strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding-shortcut-\(id)")
        .onAppear { shortcut = KeyboardShortcuts.getShortcut(for: name) }
    }

    @ViewBuilder private var keycaps: some View {
        if let shortcut {
            HStack(spacing: 3) {
                ForEach(
                    Array(PanelFirstRunStage.keycaps(for: shortcut.description).enumerated()),
                    id: \.offset
                ) { _, cap in
                    Text(verbatim: cap)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .frame(minWidth: 18, minHeight: 18)
                        .padding(.horizontal, 5)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: shortcut.description))
            .accessibilityIdentifier("onboarding-shortcut-keys-\(id)")
        } else {
            Text("Not set")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("onboarding-shortcut-keys-\(id)")
        }
    }
}
