import AppKit
import ClipboardCore
import Combine
import GanchoAI
import GanchoDesign
import GanchoKit
import SwiftUI

/// ClipPeek — a Quick-Look-style rich preview (the design's component): a
/// type-aware body, an insight strip (source app · time · expiry), the kind's
/// offline transforms, and Paste / Paste plain / Pin. Sensitive clips stay
/// masked here; revealing them takes an explicit transform.
struct ClipPeek: View {
    let item: ClipItem
    let text: String
    let isTextEditable: Bool
    /// Shared with the list: the peek owns the keyboard when this equals `.peek`
    /// (entered with → from the list, left with ←).
    var focus: FocusState<PanelFocus?>.Binding
    @Environment(AppModel.self) private var model
    @State private var actionResult: String?
    @State private var boardIDs: Set<UUID> = []
    /// Smart Paste can run the on-device model — show a spinner while it thinks.
    @State private var isThinking = false
    /// The board auto-board thinks this clip belongs to (a suggestion, never
    /// auto-filed); nil until computed or once accepted/dismissed.
    @State private var suggestedBoard: Pinboard?
    /// The highlighted action while the peek owns the keyboard (focus == .peek).
    @State private var actionIndex = 0
    /// User-authored titles are edited inline; drafts never mutate the store
    /// until Save succeeds.
    @State private var presentedTitle: String
    @State private var titleDraft: String
    @State private var isEditingTitle = false
    @State private var isSavingTitle = false
    @State private var titleSaveFailed = false
    @FocusState private var isTitleFieldFocused: Bool
    /// The current durable body. The text editor changes this only after Save;
    /// transforms and Smart Paste therefore use the just-saved value.
    @State private var presentedText: String
    /// While the multiline editor owns the keyboard, parent navigation must
    /// not intercept Return, arrows, or Escape.
    @State private var isEditingText = false

    init(
        item: ClipItem, text: String, isTextEditable: Bool,
        focus: FocusState<PanelFocus?>.Binding
    ) {
        self.item = item
        self.text = text
        self.isTextEditable = isTextEditable
        self.focus = focus
        _presentedTitle = State(initialValue: item.title)
        _titleDraft = State(initialValue: item.title)
        _presentedText = State(initialValue: text)
    }

    /// Masked clips show the canonical mask even if malformed legacy/sync
    /// metadata carries a raw preview. The peek is a preview, so cap very long
    /// clips: laying out a huge Text here on every selection change is what froze
    /// navigation on big clips (e.g. a long markdown doc).
    private var bodyText: String {
        let raw =
            ClipSafePresentation.requiresMasking(item)
            ? ClipSafePresentation.masked : presentedText
        let limit = 4000
        return raw.count > limit ? String(raw.prefix(limit)) + "\n…" : raw
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.sm) {
            header
            if titleSaveFailed {
                Text("Couldn’t save the title.")
                    .font(.caption)
                    .foregroundStyle(GanchoTokens.Palette.danger)
            }
            if let suggestedBoard {
                suggestionChip(suggestedBoard)
            }
            peekBody
            insightStrip
            if canTransform || canSmartPaste {
                HStack(spacing: GanchoTokens.Spacing.xxs) {
                    if canTransform {
                        transformsMenu
                    }
                    if canSmartPaste {
                        smartPasteMenu
                    }
                }
            }
            if isThinking {
                Label("Thinking…", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .symbolEffect(.pulse, options: .repeating)
            } else if let actionResult, !actionResult.isEmpty {
                resultBox(actionResult)
            }
            actionsList
        }
        .padding(GanchoTokens.Spacing.md)
        // Sized to its content and pinned to the top — the peek is a shorter
        // detail card, not the full height of the list.
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // The peek owns the keyboard while focus == .peek: ↑↓ move among the
        // actions, Enter runs the focused one, ← hands focus back to the list.
        .focusable()
        .focusEffectDisabled()
        .focused(focus, equals: .peek)
        .onKeyPress(.upArrow) {
            guard !isInlineEditing else { return .ignored }
            return moveAction(-1)
        }
        .onKeyPress(.downArrow) {
            guard !isInlineEditing else { return .ignored }
            return moveAction(1)
        }
        .onKeyPress(.leftArrow) {
            guard !isInlineEditing else { return .ignored }
            focus.wrappedValue = .search
            return .handled
        }
        .onKeyPress(.return) {
            guard !isInlineEditing else { return .ignored }
            runFocusedAction()
            return .handled
        }
        .onKeyPress(.escape) {
            guard !isInlineEditing else { return .ignored }
            model.panel.hide()
            return .handled
        }
        .onChange(of: focus.wrappedValue) { _, newValue in
            if newValue == .peek { actionIndex = 0 }
        }
        .onChange(of: item.title) { _, newTitle in
            guard !isEditingTitle else { return }
            presentedTitle = newTitle
            titleDraft = newTitle
        }
        .onChange(of: text) { _, newText in
            presentedText = newText
        }
        .task(id: item.id) { await model.thumbnails.ensureLoaded(item) }
        .task(id: item.id) { boardIDs = await model.boardMembership(for: item) }
        .task(id: item.id) { suggestedBoard = await model.suggestedBoard(for: item) }
    }

    /// "Add to Dev?" — the one-tap board suggestion. Accepting files the clip;
    /// the ✕ dismisses it. Auto-board never files silently.
    private func suggestionChip(_ board: Pinboard) -> some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            Image(systemName: "sparkles").foregroundStyle(GanchoTokens.Palette.accent)
            Text("Add to \(board.name)?").font(.caption.weight(.medium)).lineLimit(1)
            Spacer(minLength: 0)
            Button("Add") {
                model.assignWithUndo(item, toBoard: board)
                boardIDs.insert(board.id)
                suggestedBoard = nil
            }
            .buttonStyle(.borderless)
            Button {
                suggestedBoard = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless).foregroundStyle(.tertiary)
            .accessibilityLabel(Text("Dismiss"))
        }
        .padding(.horizontal, GanchoTokens.Spacing.sm)
        .padding(.vertical, 6)
        .background(
            GanchoTokens.Palette.accent.opacity(0.1),
            in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
        )
        .accessibilityIdentifier("board-suggestion")
    }

    /// The header doubles as the peek's drag-out handle (the text body keeps
    /// its selection gestures, so the drag lives on the title row instead).
    private var header: some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            TypeBadge(kind: item.kind)
            if isEditingTitle {
                TextField("Title", text: $titleDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTitleFieldFocused)
                    .onSubmit { saveTitle() }
                    .accessibilityIdentifier("preview-title-field")
                Button("Save") { saveTitle() }
                    .buttonStyle(.borderless)
                    .disabled(isSavingTitle)
                    .accessibilityIdentifier("preview-save-title")
                Button("Cancel") { cancelTitleEditing() }
                    .buttonStyle(.borderless)
                    .disabled(isSavingTitle)
                    .accessibilityIdentifier("preview-cancel-title")
            } else {
                Text(presentedTitle.isEmpty ? String(localized: "Untitled") : presentedTitle)
                    .font(.headline)
                    .foregroundStyle(presentedTitle.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .accessibilityIdentifier("preview-title")
                Button {
                    beginTitleEditing()
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Edit title"))
                .accessibilityIdentifier("preview-edit-title")
            }
            Spacer(minLength: 0)
            boardMenu
            Button {
                model.togglePin(item)
            } label: {
                Image(systemName: item.isPinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(item.isPinned ? "Unpin" : "Pin"))
            .accessibilityIdentifier("preview-pin")
        }
        .clipDragSource(item)
    }

    /// Toggle this clip in/out of any board, with a checkmark on the boards it
    /// already belongs to (a clip can be in several). Favorites is just another
    /// board here — the protected one.
    private var boardMenu: some View {
        Menu {
            ForEach(model.boards) { board in
                Button {
                    Task {
                        await model.setBoardMembership(
                            item, board: board, member: !boardIDs.contains(board.id))
                        boardIDs = await model.boardMembership(for: item)
                    }
                } label: {
                    Label {
                        board.isSystem ? Text("Favorites") : Text(verbatim: board.name)
                    } icon: {
                        Image(
                            systemName: boardIDs.contains(board.id) ? "checkmark" : board.sfSymbol)
                    }
                }
            }
        } label: {
            Image(systemName: boardIDs.isEmpty ? "tray" : "tray.full")
        }
        .menuIndicator(.hidden)
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("Add to board"))
        .accessibilityIdentifier("preview-board")
    }

    /// Type-aware body: colour clips show a big swatch beside the value;
    /// everything else shows its (syntax-tinted for code) text.
    @ViewBuilder private var peekBody: some View {
        if item.kind == .image, !item.isSensitive,
            let thumbnail = model.thumbnails.cached(for: item.id)
        {
            thumbnail
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 220, alignment: .topLeading)
                .clipShape(
                    RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
                )
                // Dragging the preview itself hands the full-resolution image
                // (not the thumbnail) to the drop target.
                .clipDragSource(item)
        } else if isTextEditable {
            ClipTextEditor(
                text: $presentedText, kind: item.kind,
                onEditingChanged: { editing in
                    isEditingText = editing
                    focus.wrappedValue = editing ? nil : .peek
                },
                onSave: { edited in
                    await model.updateClipText(item, text: edited)
                }
            )
            .id(item.id)
        } else if item.kind == .color, !item.isSensitive,
            let color = Color(hexString: presentedText)
        {
            HStack(spacing: GanchoTokens.Spacing.sm) {
                RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
                    .fill(color)
                    .frame(width: 56, height: 56)
                    .overlay(
                        RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
                            .strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline))
                Text(presentedText).font(.body.monospaced()).textSelection(.enabled)
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

    /// One navigable action in the peek. The action list is the keyboard
    /// surface: ↑↓ move among these, Enter runs the focused one, click runs it.
    private struct PeekAction: Identifiable {
        let id: String
        let title: LocalizedStringKey
        let symbol: String
        let run: () -> Void
    }

    /// Paste variants first (the common case), then the per-kind Dev Actions.
    /// Smart Paste keeps its own menu (it is async and has a language submenu).
    private var navActions: [PeekAction] {
        var actions: [PeekAction] = [
            PeekAction(id: "preview-paste", title: "Paste", symbol: "doc.on.clipboard") {
                model.paste(item)
            },
            PeekAction(id: "preview-paste-plain", title: "Paste plain", symbol: "doc.plaintext") {
                model.paste(item, asPlainText: true)
            }
        ]
        if !ClipSafePresentation.requiresMasking(item) {
            for action in DevActions.actions(for: item.kind) {
                actions.append(
                    PeekAction(
                        id: "dev-action-\(action.id.rawValue)",
                        title: LocalizedStringKey(action.title), symbol: "wand.and.sparkles"
                    ) {
                        actionResult = (try? action.transform(presentedText)) ?? ""
                        UserDefaults.standard.set(
                            UserDefaults.standard.integer(forKey: "dev-actions-run") + 1,
                            forKey: "dev-actions-run")
                    })
            }
        }
        return actions
    }

    /// The keyboard-navigable action list (Quick-Look-style). The focused row is
    /// highlighted only while the peek owns the keyboard (focus == .peek), so the
    /// list and the peek never look "both selected".
    private var actionsList: some View {
        // Bounded + scrollable: for code clips the per-kind Dev Actions make this
        // list long enough to push the whole peek past the fixed panel height and
        // clip the bottom (and crowd out the text preview). Cap it and let it
        // scroll internally — the preview above always stays visible; the keyboard
        // focus scrolls into view.
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(navActions.enumerated()), id: \.element.id) { index, action in
                        let isFocused = focus.wrappedValue == .peek && index == actionIndex
                        HStack(spacing: GanchoTokens.Spacing.xs) {
                            Image(systemName: action.symbol).frame(width: 16)
                            Text(action.title).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .font(.body)
                        .padding(.horizontal, GanchoTokens.Spacing.sm)
                        .padding(.vertical, 6)
                        .background(
                            isFocused
                                ? AnyShapeStyle(GanchoTokens.Palette.accent.opacity(0.18))
                                : AnyShapeStyle(.clear),
                            in: RoundedRectangle(
                                cornerRadius: GanchoTokens.Radius.sm, style: .continuous)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            actionIndex = index
                            action.run()
                        }
                        .accessibilityIdentifier(action.id)
                    }
                }
            }
            .frame(maxHeight: 180)
            .onChange(of: actionIndex) { _, new in
                guard navActions.indices.contains(new) else { return }
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(navActions[new].id, anchor: .center)
                }
            }
        }
    }

    private func moveAction(_ delta: Int) -> KeyPress.Result {
        let count = navActions.count
        guard count > 0 else { return .handled }
        actionIndex = (actionIndex + delta + count) % count
        return .handled
    }

    private func runFocusedAction() {
        guard navActions.indices.contains(actionIndex) else { return }
        navActions[actionIndex].run()
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
            HStack(spacing: GanchoTokens.Spacing.xxs) {
                ActionButton("Paste", systemImage: "doc.on.clipboard", identifier: "paste-result") {
                    model.pasteText(result)
                }
                ActionButton("Copy result", systemImage: "doc.on.doc", identifier: "copy-result") {
                    SystemPasteboardWriter().write(.text(result), asPlainText: true)
                    model.toasts.show(GanchoToast(message: "Copied"))
                }
            }
        }
    }

}

// MARK: - Smart Paste & deterministic transforms
//
// Lives in an extension so the view struct body stays inside the lint budget;
// same-file access keeps every member private.
extension ClipPeek {
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

    private var isInlineEditing: Bool {
        isEditingTitle || isEditingText
    }

    private func beginTitleEditing() {
        titleDraft = presentedTitle
        titleSaveFailed = false
        // The panel search field normally owns keyboard focus. Relinquish it
        // before presenting the inline editor, then focus the newly inserted
        // field on the next run-loop turn so typing can begin immediately.
        focus.wrappedValue = nil
        isEditingTitle = true
        Task { @MainActor in
            await Task.yield()
            guard isEditingTitle else { return }
            isTitleFieldFocused = true
        }
    }

    private func saveTitle() {
        guard !isSavingTitle else { return }
        isSavingTitle = true
        titleSaveFailed = false
        let draft = titleDraft
        Task {
            let saved = await model.updateClipTitle(item, title: draft)
            isSavingTitle = false
            guard saved else {
                titleSaveFailed = true
                return
            }
            let normalized = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            presentedTitle = normalized
            titleDraft = normalized
            isTitleFieldFocused = false
            isEditingTitle = false
            focus.wrappedValue = .peek
        }
    }

    private func cancelTitleEditing() {
        titleDraft = presentedTitle
        titleSaveFailed = false
        isTitleFieldFocused = false
        isEditingTitle = false
        focus.wrappedValue = .peek
    }

    /// Smart Paste fits text clips only and never a masked secret. Model-backed
    /// rewrites need Apple Intelligence, but deterministic PII redaction remains
    /// available whenever the user kept the Smart Paste toggle on.
    private var canSmartPaste: Bool {
        model.smartPasteAvailable && !ClipSafePresentation.requiresMasking(item)
            && item.kind != .image && item.kind != .fileReference && item.kind != .color
    }

    /// The deterministic transforms fit any text (colour hex included) and
    /// never a masked secret. Deliberately NO availability gate — they work on
    /// every Mac, with Apple Intelligence off.
    private var canTransform: Bool {
        !ClipSafePresentation.requiresMasking(item)
            && item.kind != .image && item.kind != .fileReference
    }

    /// Pure transforms with the result in the review box below (same flow as
    /// the Dev Actions): see it, then Paste or Copy. `.plainText` is omitted —
    /// it's the identity here, and "Paste plain" already covers it.
    private var transformsMenu: some View {
        Menu {
            ForEach(PasteTransform.allCases.filter { $0 != .plainText }, id: \.self) { transform in
                Button(LocalizedStringKey(transform.title)) {
                    actionResult = transform.apply(to: presentedText)
                }
            }
        } label: {
            Label("Transform", systemImage: "textformat")
                .font(.body.weight(.medium))
                .padding(.horizontal, GanchoTokens.Spacing.sm)
                .padding(.vertical, GanchoTokens.Spacing.xxs)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .ganchoSurface(radius: GanchoTokens.Radius.md)
        .accessibilityIdentifier("transform-menu")
    }

    /// On-device rewrite menu (the design's "Smart paste"): summarize, fix
    /// grammar, change tone, pull key points — the result lands in the box below
    /// for review before pasting.
    private var smartPasteMenu: some View {
        Menu {
            ForEach(SmartPasteAction.allCases) { action in
                if action == .redactPII || model.smartPasteModelAvailable {
                    Button {
                        runSmartPaste(action)
                    } label: {
                        Label(LocalizedStringKey(action.titleKey), systemImage: action.symbolName)
                    }
                }
            }
            if model.smartPasteModelAvailable {
                Divider()
                Menu {
                    ForEach(Self.translateLanguageCodes, id: \.self) { code in
                        Button(Self.localizedLanguageName(code)) {
                            runTranslate(to: Self.englishLanguageName(code))
                        }
                    }
                } label: {
                    Label("Translate to", systemImage: "globe")
                }
            }
            Divider()
            Label("Runs on your Mac — nothing leaves the device.", systemImage: "lock.shield")
        } label: {
            Label("Smart paste", systemImage: "sparkles")
                .font(.body.weight(.medium))
                .padding(.horizontal, GanchoTokens.Spacing.sm)
                .padding(.vertical, GanchoTokens.Spacing.xxs)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .ganchoSurface(radius: GanchoTokens.Radius.md)
        .disabled(isThinking)
        .accessibilityIdentifier("smart-paste-menu")
    }

    private func runSmartPaste(_ action: SmartPasteAction) {
        actionResult = nil
        isThinking = true
        Task {
            let result = await model.smartPaste(presentedText, action: action)
            isThinking = false
            actionResult = result ?? String(localized: "Couldn’t run that — try again.")
        }
    }

    /// Common targets for Smart Paste translation. Names render in the user's
    /// language (via `Locale`); the prompt gets the English name for clarity.
    private static let translateLanguageCodes = [
        "en", "es", "fr", "de", "it", "pt", "ja", "ko", "zh"
    ]
    private static func localizedLanguageName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code
    }
    private static func englishLanguageName(_ code: String) -> String {
        Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code
    }

    private func runTranslate(to language: String) {
        actionResult = nil
        isThinking = true
        Task {
            let result = await model.smartTranslate(presentedText, to: language)
            isThinking = false
            actionResult = result ?? String(localized: "Couldn’t run that — try again.")
        }
    }
}
