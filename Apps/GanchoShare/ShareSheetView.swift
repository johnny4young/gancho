import ClipboardCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// What the share sheet will save, with its title, boards and pin.
struct ShareSheetView: View {
    @Bindable var model: ShareSheetModel
    let onSave: () -> Void
    let onCancel: () -> Void
    @State private var naming = false
    @State private var draftName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section { preview }
                if model.offersTitle {
                    Section("Title") {
                        TextField("Title", text: $model.title)
                            .accessibilityIdentifier("share-title-field")
                    }
                }
                Section("Add to board") {
                    FlowLayout(spacing: 6) {
                        ForEach(model.boards) { boardChip($0) }
                        newBoardChip
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                }
                Section {
                    Toggle(isOn: $model.isPinned) {
                        Label {
                            Text("Pin it")
                        } icon: {
                            Image(systemName: "pin").foregroundStyle(GanchoTokens.Palette.accentInk)
                        }
                    }
                    .accessibilityIdentifier("share-pin-toggle")
                }
                Section {
                    saveButton
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
            }
            .tint(GanchoTokens.Palette.accent)
            .navigationTitle("Save to Gancho")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .alert("New board", isPresented: $naming) {
                TextField("Board name", text: $draftName)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                    model.newBoardName = name.isEmpty ? nil : name
                }
            }
            .alert("Couldn’t save to Gancho.", isPresented: $model.saveFailed) {
                Button("OK", role: .cancel) {}
            }
        }
        .accessibilityIdentifier("share-sheet")
    }

    /// The first capture as a history row shows it; masked kinds stay masked.
    @ViewBuilder private var preview: some View {
        if let first = model.captures.first {
            let item = Self.previewItem(for: first, masked: model.isProtected)
            HStack(spacing: GanchoTokens.Spacing.sm) {
                ClipTile(item: item, size: 36, previewsHidden: false, thumbnail: model.thumbnail)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.kind.cardName).font(.subheadline.weight(.bold))
                    if !item.preview.isEmpty {
                        Text(verbatim: item.preview)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if model.captures.count > 1 {
                    Text(verbatim: "+\(model.captures.count - 1)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("share-preview")
        }
    }

    private func boardChip(_ board: Pinboard) -> some View {
        let selected = model.selectedBoardIDs.contains(board.id)
        return Button {
            model.toggle(board)
        } label: {
            HStack(spacing: 4) {
                if selected {
                    Image(systemName: "checkmark").font(.caption2.weight(.bold))
                } else {
                    BoardIdentityMark(board: board, size: 10)
                }
                board.displayTitle
            }
            .chipStyle(selected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("share-board-chip")
    }

    @ViewBuilder private var newBoardChip: some View {
        if let name = model.newBoardName {
            Button {
                model.newBoardName = nil
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark").font(.caption2.weight(.bold))
                    Text(verbatim: name)
                }
                .chipStyle(selected: true)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isSelected)
            .accessibilityIdentifier("share-board-chip")
        } else {
            Button {
                draftName = ""
                naming = true
            } label: {
                Label("New board", systemImage: "plus")
                    .foregroundStyle(GanchoTokens.Palette.accentInk)
                    .chipStyle(selected: false)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("share-new-board")
        }
    }

    private var saveButton: some View {
        Button(action: onSave) {
            Label("Save to Gancho", systemImage: "arrow.down")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(
                    GanchoTokens.Palette.accent,
                    in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.lg, style: .continuous)
                )
                .foregroundStyle(ContrastingForeground(on: GanchoTokens.Palette.accent))
        }
        .buttonStyle(.plain)
        .disabled(model.isSaving)
        .accessibilityIdentifier("share-save-button")
    }

    /// A throwaway row for the tile and the one-line preview; never stored.
    static func previewItem(for capture: SharedInbox.PreparedCapture, masked: Bool) -> ClipItem {
        let text = capture.capture.textRepresentation ?? ""
        return ClipItem(
            kind: capture.kind ?? .text,
            preview: masked
                ? ClipSafePresentation.masked : ClipTextPreview.truncated(text, limit: 200),
            isSensitive: masked)
    }
}

extension View {
    /// The board chip: green with dark ink when chosen, a quiet fill otherwise.
    fileprivate func chipStyle(selected: Bool) -> some View {
        font(.subheadline.weight(selected ? .semibold : .medium))
            .padding(.horizontal, GanchoTokens.Spacing.sm)
            .frame(minHeight: 30)
            .background(
                selected ? AnyShapeStyle(GanchoTokens.Palette.accent) : AnyShapeStyle(.quaternary),
                in: Capsule()
            )
            .foregroundStyle(
                selected
                    ? AnyShapeStyle(ContrastingForeground(on: GanchoTokens.Palette.accent))
                    : AnyShapeStyle(.primary))
    }
}
