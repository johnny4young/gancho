import GanchoKit
import SwiftUI

/// Compact board mark shared by rows and rails. Color is never the only signal:
/// Favorites retains its SF Symbol, an optional emoji is visible as a glyph,
/// and selection remains the responsibility of the containing control.
public struct BoardIdentityMark: View {
    private let board: Pinboard
    private let size: CGFloat

    public init(board: Pinboard, size: CGFloat = 14) {
        self.board = board
        self.size = size
    }

    public var body: some View {
        if board.isSystem {
            Image(systemName: board.sfSymbol)
                .font(.system(size: size * 0.82, weight: .semibold))
                .foregroundStyle(GanchoTokens.Palette.warning)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else if let token = BoardIdentityEmoji.canonicalToken(board.emoji) {
            ZStack {
                Circle().fill(BoardColors.color(for: board).opacity(0.18))
                Text(verbatim: token).font(.system(size: size * 0.72))
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        } else {
            Circle()
                .fill(BoardColors.color(for: board))
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

/// Cross-platform board identity editor. It owns only draft UI state; the app
/// shell supplies the durable mutation so storage, diagnostics, and sync remain
/// behind the existing platform composition root.
public struct BoardIdentityEditor: View {
    @Environment(\.dismiss) private var dismiss

    private let board: Pinboard
    private let originalColorHex: String?
    private let originalEmoji: String?
    private let onSave: @MainActor (String?, String?) async -> Bool

    @State private var colorHex: String?
    @State private var emoji: String?
    @State private var isSaving = false
    @State private var showsSaveError = false

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: GanchoTokens.Spacing.sm)]
    #if os(macOS)
        private let editorMinWidth: CGFloat? = 380
        private let editorIdealWidth: CGFloat? = 420
        private let editorMinHeight: CGFloat? = 470
        private let editorIdealHeight: CGFloat? = 520
    #else
        private let editorMinWidth: CGFloat? = nil
        private let editorIdealWidth: CGFloat? = nil
        private let editorMinHeight: CGFloat? = nil
        private let editorIdealHeight: CGFloat? = nil
    #endif

    public init(
        board: Pinboard,
        onSave: @escaping @MainActor (String?, String?) async -> Bool
    ) {
        self.board = board
        self.onSave = onSave
        let colorHex = BoardIdentityColor.canonicalToken(board.colorHex)
        let emoji = BoardIdentityEmoji.canonicalToken(board.emoji)
        originalColorHex = colorHex
        originalEmoji = emoji
        _colorHex = State(initialValue: colorHex)
        _emoji = State(initialValue: emoji)
    }

    public var body: some View {
        NavigationStack {
            Form {
                previewSection
                colorSection
                emojiSection
            }
            .formStyle(.grouped)
            .navigationTitle("Board appearance")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(!hasChanges || isSaving)
                    .accessibilityIdentifier("board-appearance-save")
                }
            }
        }
        .frame(
            minWidth: editorMinWidth, idealWidth: editorIdealWidth,
            minHeight: editorMinHeight, idealHeight: editorIdealHeight
        )
        .interactiveDismissDisabled(isSaving)
        .alert("Couldn’t save changes", isPresented: $showsSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your board is unchanged. Try again.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("board-appearance-editor")
    }

    private var previewBoard: Pinboard {
        var preview = board
        preview.colorHex = colorHex
        preview.emoji = emoji
        return preview
    }

    private var hasChanges: Bool {
        colorHex != originalColorHex || emoji != originalEmoji
    }

    private var previewSection: some View {
        Section {
            HStack(spacing: GanchoTokens.Spacing.sm) {
                BoardIdentityMark(board: previewBoard, size: 36)
                VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xxs) {
                    Text(verbatim: board.name).font(.headline)
                    Text("Preview").font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var colorSection: some View {
        Section {
            LazyVGrid(columns: columns, spacing: GanchoTokens.Spacing.sm) {
                colorButton(
                    token: nil,
                    name: Text("Automatic"),
                    color: BoardColors.option(for: board).color,
                    identifier: "board-color-automatic")
                ForEach(BoardIdentityColor.allCases) { option in
                    colorButton(
                        token: option.rawValue,
                        name: Text(option.name),
                        color: option.color,
                        identifier: "board-color-\(option.id.dropFirst())")
                }
            }
            .padding(.vertical, GanchoTokens.Spacing.xs)
        } header: {
            Text("Color")
        } footer: {
            Text("Automatic stays stable for this board. Custom colors sync across your devices.")
        }
    }

    private func colorButton(
        token: String?, name: Text, color: Color, identifier: String
    ) -> some View {
        let selected = colorHex == token
        return Button {
            colorHex = token
        } label: {
            VStack(spacing: GanchoTokens.Spacing.xxs) {
                ZStack {
                    Circle().fill(color).frame(width: 36, height: 36)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .shadow(radius: 1)
                    }
                }
                name.font(.caption).lineLimit(1)
            }
            .frame(minWidth: 56, minHeight: 52)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(name)
        .accessibilityValue(selected ? Text("Selected") : Text("Not selected"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var emojiSection: some View {
        Section {
            LazyVGrid(columns: columns, spacing: GanchoTokens.Spacing.sm) {
                emojiButton(option: nil)
                ForEach(BoardIdentityEmoji.allCases) { option in
                    emojiButton(option: option)
                }
            }
            .padding(.vertical, GanchoTokens.Spacing.xs)
        } header: {
            Text("Emoji")
        } footer: {
            Text("Emoji adds a second visual cue and never replaces the board name.")
        }
    }

    private func emojiButton(option: BoardIdentityEmoji?) -> some View {
        let token = option?.rawValue
        let selected = emoji == token
        let name = option.map { Text($0.name) } ?? Text("None")
        return Button {
            emoji = token
        } label: {
            VStack(spacing: GanchoTokens.Spacing.xxs) {
                ZStack {
                    RoundedRectangle(cornerRadius: GanchoTokens.Radius.sm)
                        .fill(selected ? AnyShapeStyle(.selection) : AnyShapeStyle(.quaternary))
                        .frame(width: 44, height: 36)
                    if let token {
                        Text(verbatim: token).font(.title3)
                    } else {
                        Image(systemName: "circle.slash").foregroundStyle(.secondary)
                    }
                }
                name.font(.caption).lineLimit(1)
            }
            .frame(minWidth: 56, minHeight: 52)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("board-emoji-\(option?.id ?? "none")")
        .accessibilityLabel(name)
        .accessibilityValue(selected ? Text("Selected") : Text("Not selected"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func save() {
        guard hasChanges, !isSaving else { return }
        isSaving = true
        Task {
            let succeeded = await onSave(colorHex, emoji)
            isSaving = false
            if succeeded {
                dismiss()
            } else {
                showsSaveError = true
            }
        }
    }
}
