import AppKit
import ClipboardCore
import Combine
import GanchoAI
import GanchoDesign
import GanchoKit
import SwiftUI

/// The floating history panel: compact, keyboard-first (the explicit design
/// decision vs Paste's full-width drawer). Every interaction works without
/// a mouse: type-to-search, ↑↓, Enter, ⌥Enter, ⌘1–9, Space, Esc.
struct PanelView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @State private var results: [ClipItem] = []
    @State private var selectedIndex = 0
    @State private var previewItem: ClipItem?
    @State private var previewText = ""

    var body: some View {
        VStack(spacing: GanchoTokens.Spacing.xs) {
            SearchField("Search your clipboard", text: $query)
                .focused($searchFocused)
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-1) }
                .onKeyPress(.return, phases: .down) { press in
                    pasteSelected(plain: press.modifiers.contains(.option))
                    return .handled
                }
                .onKeyPress(.escape) {
                    model.panel.hide()
                    return .handled
                }
                .onKeyPress(characters: CharacterSet(charactersIn: "a"), phases: .down) { press in
                    // ⌘A select-all: a menu-bar agent has no Edit menu to bind it,
                    // so route selectAll: down the responder chain to the field.
                    guard press.modifiers.contains(.command) else { return .ignored }
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                    return .handled
                }
                .onKeyPress(.space) {
                    guard query.isEmpty, let item = selectedItem else { return .ignored }
                    openPreview(item)
                    return .handled
                }
                .onKeyPress(characters: .decimalDigits, phases: .down) { press in
                    guard press.modifiers.contains(.command),
                        let digit = Int(press.characters), (1...9).contains(digit),
                        results.indices.contains(digit - 1)
                    else { return .ignored }
                    model.paste(results[digit - 1])
                    return .handled
                }
                .onKeyPress(characters: CharacterSet(charactersIn: "p"), phases: .down) { press in
                    guard press.modifiers.contains(.command), let item = selectedItem else {
                        return .ignored
                    }
                    model.togglePin(item)
                    return .handled
                }
                .onKeyPress(characters: CharacterSet(charactersIn: "s"), phases: .down) { press in
                    guard press.modifiers.contains(.command), let item = selectedItem else {
                        return .ignored
                    }
                    model.promoteToSnippet(item)
                    return .handled
                }

            if results.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: GanchoTokens.Spacing.xxs) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                row(for: item, index: index)
                                    .id(item.id)
                                    .onTapGesture { model.paste(item) }
                                    .contextMenu { contextMenu(for: item) }
                            }
                        }
                        .padding(.horizontal, GanchoTokens.Spacing.xxs)
                    }
                    .onChange(of: selectedIndex) { _, index in
                        guard results.indices.contains(index) else { return }
                        proxy.scrollTo(results[index].id)
                    }
                }
            }
            SyncStatusView(status: model.syncStatus)
        }
        .padding(GanchoTokens.Spacing.sm)
        .frame(minWidth: 380, minHeight: 420)
        .ganchoSurface(radius: GanchoTokens.Radius.lg)
        .task { await refresh() }
        .onChange(of: query) { _, _ in
            Task { await refresh() }
        }
        .onChange(of: model.recentItems) { _, _ in
            Task { await refresh() }
        }
        .onAppear {
            // Defer one runloop: on the FIRST open the field editor isn't
            // ready when onAppear fires, so an immediate focus is dropped
            // (arrow keys beep). The notification below re-grabs it on every
            // key transition, which covers first open and reopens alike.
            DispatchQueue.main.async { searchFocused = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) {
            _ in
            searchFocused = true
        }
        .sheet(item: $previewItem) { item in
            PreviewSheet(item: item, text: previewText)
        }
    }

    /// First-run and no-results states — warm and instructive, never a dead end
    /// (the design's empty-states spec). Branches on whether a query is active.
    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: GanchoTokens.Spacing.xs) {
            if query.isEmpty {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(
                        GanchoTokens.Palette.success.gradient,
                        in: RoundedRectangle(
                            cornerRadius: GanchoTokens.Radius.xl, style: .continuous)
                    )
                    .padding(.bottom, GanchoTokens.Spacing.xs)
                Text("Your history starts here")
                    .font(.headline)
                Text(
                    "Copy anything — text, a link, an image — and it appears here, ready to paste again."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                Text("⌘C in any app to start")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, GanchoTokens.Spacing.xxs)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 64, height: 64)
                    .background(
                        .quaternary,
                        in: RoundedRectangle(
                            cornerRadius: GanchoTokens.Radius.xl, style: .continuous)
                    )
                    .padding(.bottom, GanchoTokens.Spacing.xs)
                Text("No matches")
                    .font(.headline)
                Text("No clips for “\(query)”. Try another word or clear the filters.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("Press esc to clear the search")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, GanchoTokens.Spacing.xxs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, GanchoTokens.Spacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(query.isEmpty ? "panel-empty-firstrun" : "panel-empty-noresults")
    }

    @ViewBuilder
    private func row(for item: ClipItem, index: Int) -> some View {
        HStack(spacing: GanchoTokens.Spacing.xxs) {
            ClipCard(
                item: item, isSelected: index == selectedIndex,
                previewsHidden: model.preferences.isPrivateModePaused)
            if item.kind == .color {
                ColorSwatch(text: item.preview)
            }
            if index < 9 {
                Text(verbatim: "⌘\(index + 1)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Pin/board assignment — the context-menu path; drag & drop arrives
    /// with the panel's Quick Look evolution.
    @ViewBuilder
    private func contextMenu(for item: ClipItem) -> some View {
        Button(item.isPinned ? "Unpin" : "Pin") {
            model.togglePin(item)
        }
        Button("Promote to Library") {
            model.promoteToSnippet(item)
        }
        Button("Add to paste stack") {
            model.pushToStack(item)
        }
        Menu("Paste as") {
            ForEach(PasteTransform.allCases, id: \.self) { transform in
                Button(LocalizedStringKey(transform.title)) {
                    model.paste(item, transform: transform)
                }
            }
        }
        Menu("Add to board") {
            ForEach(model.boards) { board in
                Button(board.name) { model.assign(item, toBoard: board) }
            }
            Divider()
            Button("New board…") {
                model.createBoard(named: String(localized: "Board"))
            }
            if item.isPinned {
                Button("Remove from board") { model.assign(item, toBoard: nil) }
            }
        }
        Button("Delete", role: .destructive) {
            model.delete(item)
        }
    }

    private var selectedItem: ClipItem? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        // Always consume arrows so focus never leaves the search field — with
        // no results there is simply nothing to move (Spotlight behavior).
        // Returning .ignored here let the arrow propagate and steal focus.
        guard !results.isEmpty else { return .handled }
        selectedIndex = (selectedIndex + delta + results.count) % results.count
        return .handled
    }

    private func pasteSelected(plain: Bool) {
        guard let item = selectedItem else { return }
        model.paste(item, asPlainText: plain)
    }

    private func openPreview(_ item: ClipItem) {
        Task {
            if case .text(let text)? = try? await model.store.content(for: item.id) {
                previewText = text
            } else {
                previewText = item.preview
            }
            previewItem = item
        }
    }

    /// Type-to-search: first keystroke already narrows; empty query shows
    /// recents (pins first, store order).
    private func refresh() async {
        if query.isEmpty {
            results = (try? await model.store.items(offset: 0, limit: 50)) ?? []
        } else if let grdb = model.grdbStore {
            results = (try? await grdb.search(ClipSearchQuery(text: query), limit: 50)) ?? []
        } else {
            let all = (try? await model.store.items(offset: 0, limit: 200)) ?? []
            results = all.filter { $0.preview.localizedCaseInsensitiveContains(query) }
        }
        selectedIndex = 0
    }
}

/// Basic Space preview (the full Quick Look experience is a later ticket)
/// plus the dev-action strip: the right transforms for the detected kind,
/// result copyable in one click. All offline.
struct PreviewSheet: View {
    let item: ClipItem
    let text: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var actionResult: String?
    @State private var isEditing = false
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.sm) {
            HStack {
                TypeBadge(kind: item.kind)
                Spacer()
                // Editing applies to text clips; binary payloads are immutable.
                if !text.isEmpty {
                    Button(isEditing ? "Save" : "Edit") {
                        if isEditing {
                            Task {
                                try? await model.grdbStore?.updateClipText(
                                    id: item.id, text: draft)
                                await model.refreshRecents()
                            }
                        } else {
                            draft = text
                        }
                        isEditing.toggle()
                    }
                    .accessibilityIdentifier("preview-edit")
                }
            }
            if isEditing {
                TextEditor(text: $draft)
                    .font(item.kind == .code ? .body.monospaced() : .body)
                    .frame(minHeight: 160)
                    .accessibilityIdentifier("preview-editor")
            } else {
                ScrollView {
                    Text(highlighted)
                        .font(item.kind == .code ? .body.monospaced() : .body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }

            let actions = DevActions.actions(for: item.kind)
            if !actions.isEmpty {
                HStack(spacing: GanchoTokens.Spacing.xxs) {
                    ForEach(actions) { action in
                        ActionButton(
                            LocalizedStringKey(action.title),
                            systemImage: "wand.and.sparkles",
                            identifier: "dev-action-\(action.id.rawValue)"
                        ) {
                            actionResult = (try? action.transform(text)) ?? ""
                            UserDefaults.standard.set(
                                UserDefaults.standard.integer(forKey: "dev-actions-run") + 1,
                                forKey: "dev-actions-run")
                        }
                    }
                }
            }

            if let actionResult, !actionResult.isEmpty {
                ScrollView {
                    Text(actionResult)
                        .font(.body.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 160)
                ActionButton(
                    "Copy result", systemImage: "doc.on.doc", identifier: "copy-result"
                ) {
                    SystemPasteboardWriter().write(.text(actionResult), asPlainText: true)
                }
            }

            ActionButton("Close", systemImage: "xmark", identifier: "preview-close") {
                dismiss()
            }
        }
        .padding(GanchoTokens.Spacing.md)
        .frame(minWidth: 420, minHeight: 280)
        .accessibilityIdentifier("preview-sheet")
    }

    /// Minimal, fully local syntax tint for code clips: keywords only.
    private var highlighted: AttributedString {
        guard item.kind == .code else { return AttributedString(text) }
        var attributed = AttributedString(text)
        let keywords = [
            "func", "let", "var", "guard", "return", "import", "def", "const",
            "SELECT", "FROM", "WHERE", "async", "await", "class", "struct",
        ]
        for keyword in keywords {
            var start = attributed.startIndex
            while let range = attributed[start...].range(of: keyword) {
                attributed[range].foregroundColor = .purple
                start = range.upperBound
            }
        }
        return attributed
    }
}

/// Inline color swatch for color clips — the preview IS the value.
struct ColorSwatch: View {
    let text: String

    var body: some View {
        RoundedRectangle(cornerRadius: GanchoTokens.Radius.sm)
            .fill(Color(hexString: text) ?? .clear)
            .frame(width: 22, height: 22)
            .overlay(
                RoundedRectangle(cornerRadius: GanchoTokens.Radius.sm)
                    .strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline)
            )
            .accessibilityLabel(Text("Color swatch"))
    }
}

extension Color {
    /// #RGB / #RRGGBB / #RRGGBBAA parser for swatches; nil for non-hex.
    init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespaces)
        guard hex.hasPrefix("#") else { return nil }
        hex.removeFirst()
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        guard hex.count == 6 || hex.count == 8,
            let value = UInt64(hex, radix: 16)
        else { return nil }
        let shift: UInt64 = hex.count == 8 ? 8 : 0
        self.init(
            red: Double((value >> (16 + shift)) & 0xFF) / 255,
            green: Double((value >> (8 + shift)) & 0xFF) / 255,
            blue: Double((value >> shift) & 0xFF) / 255)
    }
}
