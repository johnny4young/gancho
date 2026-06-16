import GanchoKit
import SwiftUI

/// The keyboard surface. Without Full Access it shows the privacy explainer;
/// with it, a control bar plus a compact one-row strip or an expanded,
/// searchable list. Tapping a clip inserts its content into the active field.
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
        .task { await model.load() }
    }

    private var keyboard: some View {
        VStack(spacing: 6) {
            controlBar
            if let note = model.note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if model.expanded {
                expandedList
            } else {
                compactRow
            }
        }
        .padding(8)
    }

    private var controlBar: some View {
        HStack(spacing: 14) {
            Button(action: model.onNextKeyboard) {
                Image(systemName: "globe")
            }
            .accessibilityLabel("Next keyboard")

            if model.expanded {
                TextField("Search clips", text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: model.searchText) { _, _ in
                        Task { await model.runSearch() }
                    }
            } else {
                Spacer()
            }

            Button(action: model.saveClipboard) {
                Image(systemName: "square.and.arrow.down")
            }
            .accessibilityLabel("Save clipboard")

            Button(action: model.toggleExpand) {
                Image(systemName: model.expanded ? "chevron.down" : "chevron.up")
            }
            .accessibilityLabel("Toggle size")

            Button(action: model.onDelete) {
                Image(systemName: "delete.left")
            }
            .accessibilityLabel("Delete")
        }
        .font(.title3)
        .buttonStyle(.plain)
    }

    private var compactRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if model.entries.isEmpty {
                    Text("Nothing here yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(model.entries) { entry in
                        Button {
                            model.insert(entry)
                        } label: {
                            Text(entry.displayText)
                                .lineLimit(1)
                                .font(.callout)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.fill.tertiary, in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var expandedList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if model.entries.isEmpty {
                    Text("Nothing here yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                }
                ForEach(model.entries) { entry in
                    Button {
                        model.insert(entry)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: entry.kind.symbolName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(entry.displayText)
                                .lineLimit(2)
                                .font(.callout)
                            Spacer(minLength: 0)
                        }
                        .contentShape(.rect)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
    }
}

/// Shown until the user grants Full Access — the honest justification.
private struct FullAccessPrompt: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
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
