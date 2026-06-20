import AppKit
import ClipboardCore
import Combine
import GanchoAI
import GanchoDesign
import GanchoKit
import SwiftUI

/// The history's type-filter rail (the design's All / Links / Code / Colors /
/// Images / Secrets pills).
enum ClipKindFilter: String, CaseIterable, Identifiable {
    case all, links, code, colors, images, secrets
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .all: "All"
        case .links: "Links"
        case .code: "Code"
        case .colors: "Colors"
        case .images: "Images"
        case .secrets: "Secrets"
        }
    }

    /// The clip kind whose tint colours the pill's dot (nil for All).
    var tintKind: ClipContentKind? {
        switch self {
        case .all: nil
        case .links: .url
        case .code: .code
        case .colors: .color
        case .images: .image
        case .secrets: .secret
        }
    }

    func matches(_ kind: ClipContentKind) -> Bool {
        switch self {
        case .all: true
        case .links: kind == .url
        case .code: kind == .code || kind == .json || kind == .uuid
        case .colors: kind == .color
        case .images: kind == .image
        case .secrets: kind == .secret || kind == .jwt || kind == .creditCard
        }
    }
}

/// The floating history panel: compact, keyboard-first (the explicit design
/// decision vs Paste's full-width drawer). Every interaction works without
/// a mouse: type-to-search, ↑↓, Enter, ⌥Enter, ⌘1–9, Space, Esc.
struct PanelView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @State private var results: [ClipItem] = []
    @State private var selectedIndex = 0
    @State private var previewText = ""
    @State private var kindFilter: ClipKindFilter = .all

    /// The rows actually shown: `results` narrowed by the active filter pill.
    private var filtered: [ClipItem] {
        kindFilter == .all ? results : results.filter { kindFilter.matches($0.kind) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: GanchoTokens.Spacing.sm) {
            listColumn
                .frame(width: 340)
            // The peek opens BESIDE the list (not a modal) and follows the
            // hovered / selected clip — Quick-Look-style.
            if let selected = selectedItem {
                ClipPeek(item: selected, text: previewText)
                    .frame(width: 360)
                    .ganchoSurface(radius: GanchoTokens.Radius.lg)
                    .transition(.opacity)
            }
        }
        .padding(GanchoTokens.Spacing.sm)
        .frame(minWidth: selectedItem == nil ? 372 : 724, minHeight: 460)
        .task {
            await refresh()
            await loadSelectedText()
        }
        .onChange(of: query) { _, _ in
            Task {
                await refresh()
                await loadSelectedText()
            }
        }
        .onChange(of: model.recentItems) { _, _ in
            Task {
                await refresh()
                await loadSelectedText()
            }
        }
        .onChange(of: selectedIndex) { _, _ in
            Task { await loadSelectedText() }
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
    }

    /// The history list: search, rows, and the sync footer. The peek lives in a
    /// sibling column (see `body`).
    private var listColumn: some View {
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
                .onKeyPress(characters: .decimalDigits, phases: .down) { press in
                    guard press.modifiers.contains(.command),
                        let digit = Int(press.characters), (1...9).contains(digit),
                        filtered.indices.contains(digit - 1)
                    else { return .ignored }
                    model.paste(filtered[digit - 1])
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

            filterRail

            if filtered.isEmpty {
                emptyState
            } else {
                recentHeader
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: GanchoTokens.Spacing.xxs) {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, item in
                                row(for: item, index: index)
                                    .id(item.id)
                                    // Hover opens the peek beside the list, no Space needed.
                                    .onHover { hovering in
                                        if hovering { selectedIndex = index }
                                    }
                                    .onTapGesture { model.paste(item) }
                                    .contextMenu { contextMenu(for: item) }
                            }
                        }
                        .padding(.horizontal, GanchoTokens.Spacing.xxs)
                    }
                    .onChange(of: selectedIndex) { _, index in
                        guard filtered.indices.contains(index) else { return }
                        proxy.scrollTo(filtered[index].id)
                    }
                }
            }
            panelFooter
        }
        .ganchoSurface(radius: GanchoTokens.Radius.lg)
    }

    /// The design's type-filter rail: All / Links / Code / Colors / Images /
    /// Secrets, "All" active by default.
    private var filterRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: GanchoTokens.Spacing.xxs) {
                ForEach(ClipKindFilter.allCases) { filter in
                    filterPill(filter)
                }
            }
            .padding(.horizontal, GanchoTokens.Spacing.xxs)
        }
    }

    private func filterPill(_ filter: ClipKindFilter) -> some View {
        let isActive = filter == kindFilter
        return Button {
            kindFilter = filter
            selectedIndex = 0
            Task { await loadSelectedText() }
        } label: {
            HStack(spacing: 4) {
                if let kind = filter.tintKind {
                    Circle()
                        .fill(GanchoTokens.Palette.kindTint(for: kind))
                        .frame(width: 6, height: 6)
                }
                Text(filter.title).font(.caption.weight(.medium))
            }
            .padding(.horizontal, GanchoTokens.Spacing.xs)
            .padding(.vertical, 3)
            .background(
                isActive ? AnyShapeStyle(GanchoTokens.Palette.accent) : AnyShapeStyle(.quaternary),
                in: Capsule()
            )
            .foregroundStyle(isActive ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("filter-\(filter.rawValue)")
    }

    /// "RECENT … N CLIPS" header above the list.
    private var recentHeader: some View {
        HStack {
            Text("Recent")
            Spacer()
            Text("\(filtered.count) clips")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.tertiary)
        .textCase(.uppercase)
        .padding(.horizontal, GanchoTokens.Spacing.xs)
    }

    /// Sync state on the left, keyboard hints on the right (the design footer).
    private var panelFooter: some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            SyncStatusView(status: model.syncStatus)
            Spacer(minLength: 0)
            Label("navigate", systemImage: "arrow.up.arrow.down")
            Label("paste", systemImage: "return")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .labelStyle(.titleAndIcon)
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

    private func row(for item: ClipItem, index: Int) -> some View {
        // ClipCard is the design's ClipRow: kind glyph (or colour swatch),
        // title/preview, pin / Universal-Clipboard markers, and the ⌘N
        // quick-paste badge for the first nine rows.
        ClipCard(
            item: item, isSelected: index == selectedIndex,
            previewsHidden: model.preferences.isPrivateModePaused,
            shortcutNumber: index < 9 ? index + 1 : nil)
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
        filtered.indices.contains(selectedIndex) ? filtered[selectedIndex] : nil
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        // Always consume arrows so focus never leaves the search field — with
        // no results there is simply nothing to move (Spotlight behavior).
        // Returning .ignored here let the arrow propagate and steal focus.
        guard !filtered.isEmpty else { return .handled }
        selectedIndex = (selectedIndex + delta + filtered.count) % filtered.count
        return .handled
    }

    private func pasteSelected(plain: Bool) {
        guard let item = selectedItem else { return }
        model.paste(item, asPlainText: plain)
    }

    /// Load the selected clip's full text for the peek beside the list. Only
    /// text-like clips need a content read; reading an image/file blob from
    /// disk on every selection change would lag navigation, so those fall back
    /// to the cheap stored preview.
    private func loadSelectedText() async {
        guard let item = selectedItem else {
            previewText = ""
            return
        }
        guard item.kind != .image, item.kind != .fileReference else {
            previewText = item.preview
            return
        }
        if case .text(let text)? = try? await model.store.content(for: item.id) {
            previewText = text
        } else {
            previewText = item.preview
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

/// ClipPeek — a Quick-Look-style rich preview (the design's component): a
/// type-aware body, an insight strip (source app · time · expiry), the kind's
/// offline transforms, and Paste / Paste plain / Pin. Sensitive clips stay
/// masked here; revealing them takes an explicit transform.
struct ClipPeek: View {
    let item: ClipItem
    let text: String
    @Environment(AppModel.self) private var model
    @State private var actionResult: String?

    /// Masked clips show their stored masked preview, not the raw content.
    private var bodyText: String { item.isSensitive ? item.preview : text }

    var body: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.sm) {
            header
            peekBody
            insightStrip
            transforms
            if let actionResult, !actionResult.isEmpty {
                resultBox(actionResult)
            }
            footer
        }
        .padding(GanchoTokens.Spacing.md)
        // Sized to its content and pinned to the top — the peek is a shorter
        // detail card, not the full height of the list.
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("clip-peek")
    }

    private var header: some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            TypeBadge(kind: item.kind)
            if !item.title.isEmpty {
                Text(item.title).font(.headline).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                model.togglePin(item)
            } label: {
                Image(systemName: item.isPinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(item.isPinned ? "Unpin" : "Pin"))
            .accessibilityIdentifier("preview-pin")
        }
    }

    /// Type-aware body: colour clips show a big swatch beside the value;
    /// everything else shows its (syntax-tinted for code) text.
    @ViewBuilder private var peekBody: some View {
        if item.kind == .color, !item.isSensitive, let color = Color(hexString: text) {
            HStack(spacing: GanchoTokens.Spacing.sm) {
                RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
                    .fill(color)
                    .frame(width: 56, height: 56)
                    .overlay(
                        RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
                            .strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline))
                Text(text).font(.body.monospaced()).textSelection(.enabled)
                Spacer(minLength: 0)
            }
        } else {
            ScrollView {
                Text(highlighted)
                    .font(item.kind == .code ? .body.monospaced() : .body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 200)
        }
    }

    /// Source app · relative time · expiry — the design's insight chips.
    private var insightStrip: some View {
        HStack(spacing: GanchoTokens.Spacing.md) {
            if let bundleID = item.sourceAppBundleID {
                Label {
                    Text(SourceApp.displayName(forBundleID: bundleID))
                } icon: {
                    if let icon = SourceApp.icon(forBundleID: bundleID) {
                        Image(nsImage: icon).resizable().frame(width: 13, height: 13)
                    } else {
                        Image(systemName: "app.dashed")
                    }
                }
                .accessibilityIdentifier("peek-source-app")
            }
            Label {
                Text(item.createdAt, style: .relative)
            } icon: {
                Image(systemName: "clock")
            }
            if let expiresAt = item.expiresAt {
                Label {
                    Text(expiresAt, style: .relative)
                } icon: {
                    Image(systemName: "hourglass")
                }
                .foregroundStyle(
                    expiresAt.timeIntervalSinceNow < 600
                        ? AnyShapeStyle(GanchoTokens.Palette.warning) : AnyShapeStyle(.secondary))
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
    }

    @ViewBuilder private var transforms: some View {
        let actions = DevActions.actions(for: item.kind)
        if !actions.isEmpty {
            HStack(spacing: GanchoTokens.Spacing.xxs) {
                ForEach(actions) { action in
                    ActionButton(
                        LocalizedStringKey(action.title), systemImage: "wand.and.sparkles",
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
    }

    private func resultBox(_ result: String) -> some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xxs) {
            ScrollView {
                Text(result)
                    .font(.body.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 140)
            ActionButton("Copy result", systemImage: "doc.on.doc", identifier: "copy-result") {
                SystemPasteboardWriter().write(.text(result), asPlainText: true)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: GanchoTokens.Spacing.xxs) {
            ActionButton("Paste", systemImage: "doc.on.clipboard", identifier: "preview-paste") {
                model.paste(item)
            }
            ActionButton(
                "Paste plain", systemImage: "doc.plaintext", identifier: "preview-paste-plain"
            ) {
                model.paste(item, asPlainText: true)
            }
            Spacer(minLength: 0)
        }
    }

    /// Fully local syntax tint for code clips, shared with the Library editor
    /// via `GanchoSyntax` (strings, comments, numbers, keywords, `{placeholder}`
    /// fields). Non-code clips render as plain text.
    private var highlighted: AttributedString {
        var attributed = AttributedString(bodyText)
        // The peek re-renders on every selection change; tokenizing a very
        // large clip there would lag navigation, so highlight only when the
        // clip is a reasonable size.
        guard item.kind == .code, bodyText.count <= 20_000 else { return attributed }
        for token in GanchoSyntax.tokens(in: bodyText) {
            let lower = bodyText.distance(from: bodyText.startIndex, to: token.range.lowerBound)
            let upper = bodyText.distance(from: bodyText.startIndex, to: token.range.upperBound)
            let lo = attributed.index(attributed.startIndex, offsetByCharacters: lower)
            let hi = attributed.index(attributed.startIndex, offsetByCharacters: upper)
            attributed[lo..<hi].foregroundColor = GanchoTokens.Syntax.color(for: token.kind)
        }
        return attributed
    }
}
