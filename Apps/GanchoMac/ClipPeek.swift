import AppKit
import ClipboardCore
import Combine
import GanchoAI
import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// ClipPeek — a Quick-Look-style rich preview (the design's component): a
/// kind-aware hero, an insight strip (source app · time · expiry · boards),
/// the kind's offline transforms, and an action dock (Paste / Paste plain /
/// Pin / Board) with the Dev Actions as chips above it. Sensitive clips stay
/// masked here; revealing them takes an explicit transform.
struct ClipPeek: View {
    let item: ClipItem
    let text: String
    let isTextEditable: Bool
    /// ⌘B: the board picker belongs to the panel, which files the whole
    /// selection; the dock's Board action just asks for it.
    let addToBoard: () -> Void
    /// ⇧⌘B: file the selection into the last board, as from the list.
    let addToLastBoard: () -> Void
    /// Tells the panel an inline editor owns the keyboard, so a window regaining
    /// key status does not pull focus back to the search field.
    @Binding var isEditingInline: Bool
    /// Bumped by the panel's ⌘T.
    let transformRequest: Int
    /// Shared with the list: the peek owns the keyboard when this equals `.peek`
    /// (entered with → from the list, left with ←).
    var focus: FocusState<PanelFocus?>.Binding
    @Environment(AppModel.self) var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var recipeRequest: TextRecipeReviewRequest?
    @State var actionResult: String?
    @State var showsTransformPopover = false
    @State var transformPipeline = TransformPipeline()
    @State private var boardIDs: Set<UUID> = []
    @State private var syncState: PeekSyncState?
    /// Smart Paste can run the on-device model — show a spinner while it thinks.
    @State var translationTargets: [TranslationDestination] = []
    @State var translationFailed = false
    @State var translationRefresh = 0
    @State var translationTask: Task<Void, Never>?
    @State var translationRequestID = UUID()
    @State var isThinking = false
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
    @State var presentedText: String
    /// While the multiline editor owns the keyboard, parent navigation must
    /// not intercept Return, arrows, or Escape.
    @State private var isEditingText = false
    /// Shared by the two OCR views (regions over the thumbnail, section under
    /// it): the line under the cursor, the line just copied, the reveal state
    /// of a recognized secret, and whether the inline editor has the keyboard.
    @State private var ocrHoveredLine: Int?
    @State private var ocrCopiedLine: Int?
    @State private var ocrRevealSecret = false
    @State private var isEditingOCR = false
    @State private var isPickingColor = false
    @State var secretReveal = SecretReveal()
    @State var secretText: String?
    /// Bumped by every hide, so a reveal read that finishes after one never shows.
    @State var secretHideCount = 0

    init(
        item: ClipItem, text: String, isTextEditable: Bool,
        focus: FocusState<PanelFocus?>.Binding, isEditingInline: Binding<Bool>,
        transformRequest: Int = 0,
        addToBoard: @escaping () -> Void, addToLastBoard: @escaping () -> Void
    ) {
        self.item = item
        self.text = text
        self.isTextEditable = isTextEditable
        self.focus = focus
        _isEditingInline = isEditingInline
        self.transformRequest = transformRequest
        self.addToBoard = addToBoard
        self.addToLastBoard = addToLastBoard
        _presentedTitle = State(initialValue: item.title)
        _titleDraft = State(initialValue: item.title)
        _presentedText = State(initialValue: text)
    }

    var hidesPreview: Bool {
        model.previewsHidden || ClipSafePresentation.requiresMasking(item)
    }

    /// Masked clips show the canonical mask even if malformed legacy/sync
    /// metadata carries a raw preview. The peek is a preview, so cap very long
    /// clips: laying out a huge Text here on every selection change is what froze
    /// navigation on big clips (e.g. a long markdown doc).
    private var bodyText: String {
        let raw =
            ClipSafePresentation.requiresMasking(item)
            ? ClipSafePresentation.masked : presentedText
        return ClipTextPreview.truncated(raw, limit: 4_000)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.sm) {
            header
            if titleSaveFailed {
                Text("Couldn’t save the title.")
                    .panelFont(.caption)
                    .foregroundStyle(GanchoTokens.Palette.danger)
            }
            if model.preferences.isPrivateModePaused {
                PeekPrivateModeNotice()
            } else if showsSecretHero {
                secretSection
            } else if hidesPreview {
                Text(verbatim: ClipSafePresentation.masked)
                    .panelFont(.body)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .accessibilityIdentifier("peek-masked")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: GanchoTokens.Spacing.sm) {
                        if let suggestedBoard {
                            suggestionChip(suggestedBoard)
                                .transition(GanchoMotion.replace(reduceMotion: reduceMotion))
                        }
                        hero
                        if ocrShowsHere {
                            PeekImageTextSection(
                                item: item, hoveredLine: $ocrHoveredLine,
                                copiedLine: $ocrCopiedLine,
                                revealSecret: $ocrRevealSecret, isEditing: $isEditingOCR)
                        }
                        if canTransform || canSmartPaste { transformButton }
                        if !transformPipeline.isEmpty { pipelineSection }
                        if translationFailed { translationUnavailableMessage }
                        if isThinking {
                            Label("Thinking…", systemImage: "sparkles")
                                .panelFont(.caption)
                                .foregroundStyle(.secondary)
                                .symbolEffect(.pulse, options: .repeating)
                                .transition(GanchoMotion.replace(reduceMotion: reduceMotion))
                        } else if let actionResult, !actionResult.isEmpty {
                            resultBox(actionResult)
                                .transition(GanchoMotion.replace(reduceMotion: reduceMotion))
                        }
                    }
                    // Scoped to the three things that come and go inside
                    // the peek; a global transaction would also move the
                    // editor and the scroll position.
                    .animation(peekContentAnimation, value: suggestedBoard?.id)
                    .animation(peekContentAnimation, value: isThinking)
                    .animation(peekContentAnimation, value: actionResult)
                }
            }
            dock
        }
        .padding(GanchoTokens.Spacing.md)
        // Scroll the content independently so editing, OCR and board chips cannot
        // push the dock outside a compact panel.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        .onKeyPress(.return, phases: .down) { press in
            guard !isInlineEditing else { return .ignored }
            if press.modifiers.contains(.option), !press.modifiers.contains(.command) {
                model.paste(item, asPlainText: true)
            } else if press.modifiers.contains(.shift), let result = pendingResult {
                if !transformPipeline.isEmpty { rememberPipeline() }
                model.pasteText(result)
            } else if press.modifiers.contains(.shift), let convert = convertAction {
                convert.run()
            } else {
                runFocusedAction()
            }
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "pPbB"), phases: .down) { press in
            // Same modifier semantics as the list's handlers, including ⇧⌘B.
            guard !isInlineEditing, press.modifiers.contains(.command) else { return .ignored }
            if press.characters.lowercased() == "p" {
                model.togglePin(item)
            } else if press.modifiers.contains(.shift) {
                addToLastBoard()
            } else {
                addToBoard()
            }
            return .handled
        }
        // ⌫ arrives as the system Delete command; the undo toast takes it back.
        .onDeleteCommand {
            guard !isInlineEditing else { return }
            model.delete(item)
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "iI"), phases: .down) { press in
            guard !isInlineEditing, press.modifiers.isEmpty, canPickColor else { return .ignored }
            isPickingColor.toggle()
            return .handled
        }
        .onKeyPress(.escape) {
            guard !isInlineEditing else { return .ignored }
            // esc puts the eyedropper down, then closes a transform, before it hides the panel.
            if isPickingColor {
                isPickingColor = false
            } else if !transformPipeline.isEmpty || actionResult != nil {
                closeTransform()
            } else {
                model.panel.hide()
            }
            return .handled
        }
        .onChange(of: focus.wrappedValue) { _, newValue in
            if newValue == .peek { actionIndex = 0 }
        }
        .onChange(of: transformRequest) { _, _ in
            if canTransform || canSmartPaste { showsTransformPopover = true }
        }
        // A new request (same clip, run again) starts from a clean section.
        .onChange(of: model.manualOCR.requestID) { _, _ in
            ocrHoveredLine = nil
            ocrCopiedLine = nil
            ocrRevealSecret = false
            isEditingOCR = false
        }
        // The result is transient and lives exactly as long as this clip stays
        // selected: leaving the clip, or hiding the panel, discards it.
        .onDisappear {
            if model.manualOCR.itemID == item.id { model.manualOCR.cancel() }
        }
        .onChange(of: item.title) { _, newTitle in
            guard !isEditingTitle else { return }
            presentedTitle = newTitle
            titleDraft = newTitle
        }
        .onChange(of: text) { _, newText in
            presentedText = newText
        }
        .task(id: secretReveal) {
            guard let until = secretReveal.until else { return }
            try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            endSecretReveal()
        }
        .onReceive(NotificationCenter.default.publisher(for: .ganchoPanelDidHide)) { _ in
            endSecretReveal()
        }
        // Sharing or private mode: a revealed secret masks at once.
        .onChange(of: model.secretRevealAllowed) { _, allowed in
            if !allowed { endSecretReveal() }
        }
        .onChange(of: hidesPreview) { _, hidden in
            if hidden {
                transformPipeline = TransformPipeline()
                isEditingTitle = false
                isEditingText = false
                isEditingOCR = false
                actionResult = nil
                actionIndex = 0
                // The torn-down editor never hands focus back itself.
                if focus.wrappedValue == nil { focus.wrappedValue = .peek }
            }
        }
        .onChange(of: isInlineEditing, initial: true) { _, editing in
            isEditingInline = editing
        }
        .onDisappear { isEditingInline = false }
        .task(id: translationAvailabilityRequest) { await refreshTranslationTargets() }
        // The panel's hosting view has no scene phase; re-check pairs on every show.
        .onReceive(NotificationCenter.default.publisher(for: .ganchoPanelDidShow)) { _ in
            translationRefresh += 1
        }
        .onDisappear { translationTask?.cancel() }
        .onChange(of: presentedText) { _, _ in
            translationTargets = []
            translationTask?.cancel()
            translationRequestID = UUID()
            isThinking = false
            translationFailed = false
        }
        .task(id: ClipContentVersion(item)) { await model.thumbnails.ensureLoaded(item) }
        .task(id: item) {
            let membership = await model.boardMembership(for: item)
            guard !Task.isCancelled else { return }
            boardIDs = membership
        }
        .task(id: item.id) { await loadSuggestedBoard() }
        .task(id: PeekSyncStateKey(id: item.id, status: model.syncStatus)) {
            // A masked clip never shows the chip, so it is not looked up.
            var state: PeekSyncState?
            if !hidesPreview { state = await model.uploadState(for: item) }
            guard !Task.isCancelled else { return }
            syncState = state
        }
    }

    /// "Add to Dev?" — the one-tap board suggestion. Accepting files the clip;
    /// the ✕ dismisses it. Auto-board never files silently.
    private func suggestionChip(_ board: Pinboard) -> some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            Image(systemName: "sparkles").foregroundStyle(GanchoTokens.Palette.accentInk)
            Text("Add to \(board.name)?").panelFont(.subheadline, .medium).lineLimit(1)
            Spacer(minLength: 0)
            Button("Add") {
                model.assign(item, toBoard: board)
                suggestedBoard = nil
            }
            .ganchoTextButton()
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

    /// Provenance first, then the title on its own row.
    private var header: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            PeekProvenanceHeader(
                item: item,
                boards: Array(model.boards.filter { boardIDs.contains($0.id) }.prefix(3)),
                syncState: syncState, masksProvenance: hidesPreview,
                showsExpiry: !showsSecretHero)
            titleRow
        }
    }

    /// The title row doubles as the peek's drag-out handle (the text body
    /// keeps its selection gestures).
    private var titleRow: some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            if showsSecretHero {
                Text(item.kind.cardName)
                    .panelFont(.headline)
                    .accessibilityIdentifier("preview-title")
            } else if hidesPreview {
                Text(verbatim: ClipSafePresentation.masked)
                    .panelFont(.headline)
                    .accessibilityIdentifier("preview-title")
            } else if isEditingTitle {
                TextField("Title", text: $titleDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTitleFieldFocused)
                    .onSubmit { saveTitle() }
                    .accessibilityIdentifier("preview-title-field")
                Button("Save") { saveTitle() }
                    .ganchoTextButton()
                    .disabled(isSavingTitle)
                    .accessibilityIdentifier("preview-save-title")
                Button("Cancel") { cancelTitleEditing() }
                    .keyboardShortcut(.cancelAction)
                    .ganchoTextButton()
                    .disabled(isSavingTitle)
                    .accessibilityIdentifier("preview-cancel-title")
            } else {
                Text(presentedTitle.isEmpty ? String(localized: "Untitled") : presentedTitle)
                    .panelFont(.headline)
                    .foregroundStyle(presentedTitle.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .accessibilityIdentifier("preview-title")
                Button {
                    beginTitleEditing()
                } label: {
                    Image(systemName: "pencil")
                }
                .ganchoTextButton()
                .accessibilityLabel(Text("Edit title"))
                .accessibilityIdentifier("preview-edit-title")
            }
            Spacer(minLength: 0)
        }
        .clipDragSource(item)
    }
}

// MARK: - Hero

extension ClipPeek {
    /// The kind-aware hero card: the image with its Live-Text regions, a link's
    /// host and original URL (parsed locally, never fetched), the colour hero,
    /// or the (syntax-tinted) text. The card takes a wash of the kind's tint.
    private var hero: some View {
        let tint = GanchoTokens.Palette.kindTint(for: item.kind)
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.lg, style: .continuous)
        return VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            if let parts = linkParts, !isEditingText {
                PeekLinkHero(parts: parts)
            }
            if let color = colorValue, !isEditingText {
                PeekColorHero(color: color) { value, label in
                    model.copyColorFormat(value, label: label)
                }
            }
            heroBody
        }
        .padding(GanchoTokens.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                shape.fill(.quaternary.opacity(0.35))
                shape.fill(
                    RadialGradient(
                        colors: [tint.opacity(0.2), .clear], center: .topLeading,
                        startRadius: 0, endRadius: 360))
            }
        }
        .overlay(
            shape.strokeBorder(.separator.opacity(0.6), lineWidth: GanchoTokens.Stroke.hairline)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("peek-hero")
    }

    /// Non-nil only when a link clip's text really parses as a URL with a
    /// host; a `url`-kind clip whose text doesn't (synthetic or edited) keeps
    /// the plain body.
    private var linkParts: ClipLinkParts? {
        guard item.kind == .url, !ClipSafePresentation.requiresMasking(item) else { return nil }
        return ClipLinkParts(text: presentedText)
    }

    private var colorValue: ColorValue? {
        guard item.kind == .color, !ClipSafePresentation.requiresMasking(item) else { return nil }
        return ColorValue.parse(presentedText)
    }

    @ViewBuilder private var heroBody: some View {
        if item.kind == .image, !item.isSensitive,
            let thumbnail = model.thumbnails.cached(for: item)
        {
            PeekImageStage(
                item: item, thumbnail: thumbnail, hoveredLine: $ocrHoveredLine,
                copiedLine: $ocrCopiedLine, revealSecret: $ocrRevealSecret,
                isPickingColor: $isPickingColor)
        } else if isTextEditable {
            ClipTextEditor(
                text: $presentedText, kind: item.kind,
                // The link hero already shows the URL; the editor keeps only
                // its Edit affordance until editing starts.
                readViewHidden: linkParts != nil,
                onEditingChanged: { editing in
                    isEditingText = editing
                    focus.wrappedValue = editing ? nil : .peek
                },
                onSave: { edited in
                    await model.updateClipText(item, text: edited)
                }
            )
            .id(item.id)
        } else if linkParts == nil, colorValue == nil {
            ScrollView {
                Text(highlighted)
                    .panelFont(.body, design: item.kind == .code ? .monospaced : .default)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 200)
        }
    }
}

// MARK: - Action dock and chips

extension ClipPeek {
    /// The action dock: Paste is always the prominent button (Return runs it);
    /// the keyboard-focused one — only while the peek owns the keyboard —
    /// takes a ring, so the list and the peek never look "both selected".
    private var dock: some View {
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.lg, style: .continuous)
        return HStack(spacing: GanchoTokens.Spacing.xxs) {
            ForEach(Array(dockActions.enumerated()), id: \.element.id) {
                index, action in
                actionButton(action, index: index, style: .dock(isPrimary: index == 0))
            }
        }
        .padding(GanchoTokens.Spacing.xxs)
        .background(.quaternary.opacity(0.5), in: shape)
        .overlay(
            shape.strokeBorder(.separator.opacity(0.6), lineWidth: GanchoTokens.Stroke.hairline)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("peek-dock")
    }

    /// Arrowing through rows must not compute an embedding per row.
    private func loadSuggestedBoard() async {
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        suggestedBoard = await model.suggestedBoard(for: item)
    }

    func actionButton(
        _ action: PeekAction, index: Int, style: PeekActionButton.Style
    ) -> some View {
        PeekActionButton(
            action: action, style: style,
            isFocused: focus.wrappedValue == .peek && index == actionIndex
        ) {
            actionIndex = index
            action.run()
        }
    }

}

// MARK: - Smart Paste & deterministic transforms

extension ClipPeek {
    /// Fully local syntax tint for code clips, shared with the Library editor
    /// via `GanchoSyntax` (strings, comments, numbers, keywords, `{placeholder}`
    /// fields). Non-code clips render as plain text.
    private var highlighted: AttributedString {
        // The peek re-renders on every selection change; tokenizing a very
        // large clip there would lag navigation, so highlight only when the
        // clip is a reasonable size.
        guard item.kind == .code, bodyText.count <= 20_000 else {
            return AttributedString(bodyText)
        }
        return GanchoTokens.Syntax.highlighted(bodyText)
    }

    private var isInlineEditing: Bool {
        isEditingTitle || isEditingText || isEditingOCR
    }

    var peekContentAnimation: Animation? {
        GanchoMotion.smooth(reduceMotion: reduceMotion)
    }

    /// The OCR session belongs to THIS clip and has something to show.
    private var ocrShowsHere: Bool {
        model.manualOCR.itemID == item.id && model.manualOCR.state != .idle
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
    var canSmartPaste: Bool {
        model.smartPasteAvailable && isTextEditable && !hidesPreview
            && item.kind != .image && item.kind != .fileReference && item.kind != .color
    }

    /// The deterministic transforms fit any text (colour hex included) and
    /// never a masked secret. Deliberately NO availability gate — they work on
    /// every Mac, with Apple Intelligence off.
    var canTransform: Bool {
        !hidesPreview
            && item.kind != .image && item.kind != .fileReference
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
                    .accessibilityIdentifier("intelligence-result-text")
                    .panelFont(.body, design: .monospaced)
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

// MARK: - Keyboard actions

extension ClipPeek {
    /// The keyboard order: the dock, then a secret's actions. Transforms live
    /// behind ⌘T.
    private var navActions: [PeekAction] { dockActions + secretActions }

    /// Paste variants first (the common case), then OCR, Pin and Board.
    var dockActions: [PeekAction] {
        var actions: [PeekAction] = [
            PeekAction(
                id: "preview-paste", title: pasteTitle,
                symbol: model.pasteTarget.label == .copy ? "doc.on.doc" : "doc.on.clipboard",
                shortcut: "⏎"
            ) {
                model.paste(item)
            },
            PeekAction(
                id: "preview-paste-plain", title: "Paste plain", symbol: "doc.plaintext",
                shortTitle: "Plain", shortcut: "⌥⏎"
            ) {
                model.paste(item, asPlainText: true)
            }
        ]
        if let convertAction { actions.append(convertAction) }
        // APPENDED, never inserted at 0: `actionIndex` resets to 0 whenever peek
        // takes focus and Return runs `navActions[actionIndex]`, so position 0 IS
        // the default keyboard action. Putting OCR there would silently turn
        // Return on an image clip from Paste into Copy text from image.
        if model.canCopyImageText(item) {
            actions.append(
                PeekAction(
                    id: "image-copy-text", title: "Copy text from image", symbol: "text.viewfinder",
                    shortTitle: "Copy text", shortcut: "⇧⌘C"
                ) { model.copyImageText(item, surface: .peek) })
        }
        actions.append(
            PeekAction(
                id: "preview-pin", title: item.isPinned ? "Unpin" : "Pin",
                symbol: item.isPinned ? "pin.slash" : "pin", shortcut: "⌘P"
            ) { model.togglePin(item) })
        actions.append(
            PeekAction(
                id: "preview-board", title: "Add to board", symbol: "tray", shortTitle: "Board",
                shortcut: "⌘B"
            ) { addToBoard() })
        return actions
    }

    private var pasteTitle: LocalizedStringKey {
        switch model.pasteTarget.label {
        case .pasteInto(let app): "Paste into \(app)"
        case .paste: "Paste"
        case .copy: "Copy"
        }
    }

    /// A colour clip's Convert, a dock action with ⇧⏎; its formats open in the result box.
    private var convertAction: PeekAction? {
        guard colorValue != nil, !hidesPreview else { return nil }
        return PeekAction(
            id: "preview-convert", title: "Convert", symbol: "arrow.triangle.2.circlepath",
            shortcut: "⇧⏎"
        ) {
            actionResult = try? DevActions.run(.convertColor, on: presentedText)
        }
    }

    private var canPickColor: Bool {
        item.kind == .image && !hidesPreview && model.thumbnails.cached(for: item) != nil
    }
}
