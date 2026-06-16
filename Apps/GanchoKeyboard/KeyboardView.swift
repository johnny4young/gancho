import GanchoKit
import SwiftUI

/// The keyboard surface. Without Full Access it shows the privacy explainer;
/// with it, a control bar plus a compact one-row strip or an expanded,
/// searchable list of cards. Tapping a clip inserts its text (or copies its
/// image to the pasteboard) into the active field.
struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        Group {
            if model.hasFullAccess {
                keyboard
            } else {
                FullAccessPrompt()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .task { await model.load() }
    }

    private var keyboard: some View {
        VStack(spacing: 8) {
            controlBar
            if let note = model.note {
                Label(note, systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
            if model.expanded {
                expandedList
            } else {
                compactRow
            }
        }
        .padding(10)
        .animation(.easeInOut(duration: 0.15), value: model.note != nil)
        .animation(.snappy(duration: 0.22), value: model.expanded)
        .animation(.snappy(duration: 0.22), value: model.entries)
    }

    // MARK: - Control bar

    private var controlBar: some View {
        HStack(spacing: 10) {
            iconButton("globe", label: "Next keyboard", action: model.onNextKeyboard)

            if model.expanded {
                TextField("Search clips", text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: model.searchText) { _, _ in
                        Task { await model.runSearch() }
                    }
            } else {
                Spacer(minLength: 0)
            }

            // Action cluster: clearly spaced, with the primary save tinted.
            HStack(spacing: 8) {
                saveButton
                iconButton(
                    model.expanded ? "chevron.down" : "chevron.up",
                    label: "Toggle size", action: model.toggleExpand)
                iconButton("delete.left", label: "Delete", action: model.onDelete)
            }
        }
    }

    private var saveButton: some View {
        Button(action: model.saveClipboard) {
            Group {
                if model.saving {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            .font(.body.weight(.medium))
            .frame(width: 42, height: 36)
            .background(.tint.opacity(0.18), in: .rect(cornerRadius: 10))
            .contentShape(.rect)
        }
        .buttonStyle(PressableScale())
        .foregroundStyle(.tint)
        .accessibilityLabel("Save clipboard")
    }

    private func iconButton(
        _ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body)
                .frame(width: 42, height: 36)
                .contentShape(.rect)
        }
        .buttonStyle(PressableScale())
        .foregroundStyle(.primary)
        .accessibilityLabel(label)
    }

    // MARK: - Clip lists

    private var compactRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if model.entries.isEmpty {
                    emptyLabel
                } else {
                    ForEach(model.entries) { entry in
                        Button {
                            model.insert(entry)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: entry.kind.symbolName)
                                    .font(.caption2)
                                    .foregroundStyle(.tint)
                                Text(entry.displayText)
                                    .lineLimit(1)
                                    .font(.callout)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(.fill.tertiary, in: .capsule)
                            .contentShape(.capsule)
                        }
                        .buttonStyle(PressableScale())
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var expandedList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                if model.entries.isEmpty {
                    emptyLabel.padding(.vertical, 12)
                }
                ForEach(model.entries) { entry in
                    Button {
                        model.insert(entry)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: entry.kind.symbolName)
                                .font(.footnote)
                                .foregroundStyle(.tint)
                                .frame(width: 22)
                            Text(entry.displayText)
                                .lineLimit(2)
                                .font(.callout)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(.fill.quaternary, in: .rect(cornerRadius: 12))
                        .contentShape(.rect)
                    }
                    .buttonStyle(PressableScale())
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var emptyLabel: some View {
        Text("Nothing here yet")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }
}

/// Press feedback for every tappable surface in the keyboard: a quick scale +
/// dim on touch-down so the intent ("this inserts / this acts") reads
/// instantly — the affordance a flat keyboard was missing.
struct PressableScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .opacity(configuration.isPressed ? 0.65 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Shown until the user grants Full Access — the honest justification.
private struct FullAccessPrompt: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.largeTitle)
                .foregroundStyle(.tint)
            Text("Full Access needed")
                .font(.headline)
            Text(
                "Turn on Full Access in Settings → General → Keyboard → Keyboards → Gancho. Nothing you copy or type ever leaves your device."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
