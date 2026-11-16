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
    /// Lists the clips copied around this one; nil while that list shows.
    let showContext: (() -> Void)?
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
    /// The dock verbs the row has room for; empty until the dock reports.
    @State var visibleDockIDs: [String] = []
    @Environment(\.panelTypeScale) var typeScale
    @State var transformPipeline = TransformPipeline()
    @State var describeMode = false
    @State var describedChange: DescribedChange?
    @State var describeRequest = UUID()
    /// A transform's own text field (a change request, a recipe name) has the keyboard.
    @State var isEditingTransformField = false
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
    @State private var isRewritingParts = false
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
        addToBoard: @escaping () -> Void, addToLastBoard: @escaping () -> Void,
        showContext: (() -> Void)? = nil
    ) {
        self.item = item
        self.text = text
        self.isTextEditable = isTextEditable
        self.focus = focus
        _isEditingInline = isEditingInline
        self.transformRequest = transformRequest
        self.addToBoard = addToBoard
        self.addToLastBoard = addToLastBoard
        self.showContext = showContext
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
                        hero
                        if let mergedParts, let parts = item.parts, !isEditingText {
                            PeekPartsControls(
                                separator: parts.separator, partCount: mergedParts.count,
                                isBusy: isRewritingParts, choose: rejoinParts,
                                split: splitParts)
                        }
                        if ocrShowsHere {
                            PeekImageTextSection(
                                item: item, hoveredLine: $ocrHoveredLine,
                                copiedLine: $ocrCopiedLine,
                                revealSecret: $ocrRevealSecret, isEditing: $isEditingOCR)
                        }
                        if !transformPipeline.isEmpty { pipelineSection }
                        if describeMode { describeSection }
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
                // A gutter scroller narrows an aspect-fit image until it stops
                // overflowing, then hides and lets it grow: a layout loop that freezes the panel.
                .scrollIndicators(item.kind == .image ? .never : .automatic)
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
            if press.modifiers.contains(.option), press.modifiers.contains(.command) {
                model.pushToStack(item)
            } else if press.modifiers.contains(.option) {
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
            } else if !transformPipeline.isEmpty || actionResult != nil || describeMode {
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
            if offersTransforms { showsTransformPopover = true }
        }
        // A verb that folds away must not keep the keyboard focus.
        .onChange(of: visibleDockIDs) { _, _ in
            actionIndex = min(actionIndex, max(0, navActions.count - 1))
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
            if describeMode { closeTransform() }
        }
        // Sharing or private mode: a revealed secret masks at once.
        .onChange(of: model.secretRevealAllowed) { _, allowed in
            if !allowed { endSecretReveal() }
        }
        .onChange(of: hidesPreview) { _, hidden in
            if hidden {
                closeTransform()
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
            // A rewrite of the previous text must never paste over the edit.
            if describeMode { closeTransform() }
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

    /// The board suggestion, the hero card's last row. Accepting files the
    /// clip; the ✕ dismisses it. Auto-board never files silently.
    private func suggestionRow(_ board: Pinboard) -> some View {
        let name = Text(verbatim: board.name).fontWeight(.semibold)
            .foregroundStyle(GanchoTokens.Palette.ink)
        return HStack(spacing: GanchoTokens.Spacing.xs) {
            Image(systemName: "tray")
            Text("Looks like your \(name) board").lineLimit(1)
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
            .buttonStyle(.borderless).foregroundStyle(GanchoTokens.Palette.ink3)
            .accessibilityLabel(Text("Dismiss"))
        }
        .panelFont(.subheadline)
        .foregroundStyle(GanchoTokens.Palette.ink2)
        .padding(.horizontal, GanchoTokens.Spacing.sm)
        .frame(minHeight: 36)
        .background(
            GanchoTokens.Palette.controlFill,
            in: UnevenRoundedRectangle(
                bottomLeadingRadius: GanchoTokens.Radius.lg,
                bottomTrailingRadius: GanchoTokens.Radius.lg, style: .continuous)
        )
        .overlay(alignment: .top) {
            Rectangle().fill(GanchoTokens.Palette.hairline)
                .frame(height: GanchoTokens.Stroke.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("board-suggestion")
    }

    /// Provenance first, then the title on its own row.
    private var header: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xxs) {
            PeekProvenanceHeader(
                item: item,
                // Favorites is the title row's star, so the caption skips it.
                boards: Array(
                    model.boards.filter { boardIDs.contains($0.id) && !$0.isSystem }.prefix(3)),
                syncState: syncState, masksProvenance: hidesPreview,
                showsExpiry: !showsSecretHero)
            titleRow
        }
    }

    private var favoriteButton: some View {
        let isFavorite = boardIDs.contains(Pinboard.favoritesID)
        return Button {
            guard let favorites = model.boards.first(where: { $0.id == Pinboard.favoritesID })
            else { return }
            Task {
                _ = await model.setBoardMembership(item, board: favorites, member: !isFavorite)
                boardIDs = await model.boardMembership(for: item)
            }
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
        }
        .ganchoTextButton()
        .accessibilityLabel(Text("Favorites"))
        .accessibilityAddTraits(isFavorite ? .isSelected : [])
        .accessibilityIdentifier("preview-favorite")
    }

    /// The title row doubles as the peek's drag-out handle (the text body
    /// keeps its selection gestures).
    private var titleRow: some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            if showsSecretHero {
                Text(item.kind.cardName)
                    .panelFont(size: 27, design: .serif)
                    .accessibilityIdentifier("preview-title")
            } else if hidesPreview {
                Text(verbatim: ClipSafePresentation.masked)
                    .panelFont(size: 27, design: .serif)
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
                    .panelFont(size: 27, design: .serif)
                    .foregroundStyle(
                        presentedTitle.isEmpty
                            ? GanchoTokens.Palette.ink3 : GanchoTokens.Palette.ink
                    )
                    .lineLimit(1)
                    .accessibilityIdentifier("preview-title")
                Spacer(minLength: GanchoTokens.Spacing.xs)
                Button {
                    beginTitleEditing()
                } label: {
                    Image(systemName: "pencil")
                }
                .ganchoTextButton()
                .accessibilityLabel(Text("Edit title"))
                .accessibilityIdentifier("preview-edit-title")
                favoriteButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipDragSource(item)
    }
}

// MARK: - Hero

extension ClipPeek {
    /// The kind-aware hero card: the image with its Live-Text regions, a link's
    /// host and original URL (parsed locally, never fetched), the colour hero,
    /// or the (syntax-tinted) text. The card is neutral: only content brings colour.
    private var hero: some View {
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.lg, style: .continuous)
        let link = isEditingText ? nil : linkParts
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
                if let link {
                    let markdown = link.markdownLink(title: presentedTitle)
                    PeekLinkHero(
                        parts: link, anatomy: LinkAnatomy(text: link.text), markdown: markdown
                    ) {
                        model.writeManualText(markdown)
                        model.toasts.show(GanchoToast(message: "Copied"))
                    }
                }
                if let color = colorValue, !isEditingText {
                    PeekColorHero(color: color) { value, label in
                        model.copyColorFormat(value, label: label)
                    }
                }
                heroBody
            }
            .padding(link == nil ? GanchoTokens.Spacing.sm : GanchoTokens.Spacing.md)
            if let suggestedBoard {
                suggestionRow(suggestedBoard)
                    .transition(GanchoMotion.replace(reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(GanchoTokens.Palette.controlFill, in: shape)
        .overlay(
            shape.strokeBorder(
                GanchoTokens.Palette.hairline, lineWidth: GanchoTokens.Stroke.hairline)
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

    /// The parts of a merged clip while its text still matches them.
    private var mergedParts: [String]? {
        guard isTextEditable, !hidesPreview, presentedText.count <= 4_000 else { return nil }
        return item.parts?.split(presentedText)
    }

    private func rejoinParts(_ separator: ClipParts.Separator) {
        guard !isRewritingParts else { return }
        isRewritingParts = true
        Task { @MainActor in
            _ = await model.rejoinParts(item, with: separator)
            isRewritingParts = false
        }
    }

    private func splitParts() {
        guard !isRewritingParts else { return }
        isRewritingParts = true
        Task { @MainActor in
            await model.splitParts(item)
            isRewritingParts = false
        }
    }

    var colorValue: ColorValue? {
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
                parts: mergedParts,
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
    /// The action dock, one row: Return's verb is the only filled control, the
    /// others are quiet text with their keys, and Actions closes the row. The
    /// widest tier that fits wins; what it leaves out moves into Actions.
    private var dock: some View {
        let actions = dockActions
        let tiers = PeekDockFold.tiers(
            for: actions.map(\.id), primaryHasShortTitle: actions.first?.shortTitle != nil)
        return ViewThatFits(in: .horizontal) {
            ForEach(tiers, id: \.self) { tier in
                dockRow(actions, tier: tier)
            }
        }
        .onPreferenceChange(DockVisibleIDs.self) { [shown = $visibleDockIDs] ids in
            shown.wrappedValue = ids
        }
        .sheet(item: $recipeRequest) { request in
            TextRecipeReview(clipID: request.clipID).environment(model)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("peek-dock")
    }

    private func dockRow(_ actions: [PeekAction], tier: PeekDockFold.Tier) -> some View {
        let visible = tier.visible
        let folded = PeekDockFold.folded(from: actions.map(\.id), showing: visible)
        let shown = actions.filter { visible.contains($0.id) }
        return HStack(spacing: GanchoTokens.Spacing.xxs) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, action in
                actionButton(
                    action, index: index,
                    style: .dock(isPrimary: index == 0, short: tier.shortPrimary))
            }
            Spacer(minLength: 0)
            if offersTransforms || !folded.isEmpty {
                actionsButton(folded: actions.filter { folded.contains($0.id) })
            }
        }
        .preference(key: DockVisibleIDs.self, value: visible)
    }

    /// The dock verbs in the row right now: the keyboard moves among these.
    var shownDockActions: [PeekAction] {
        let actions = dockActions
        let shown = actions.filter { visibleDockIDs.contains($0.id) }
        return shown.isEmpty ? actions : shown
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
        isEditingTitle || isEditingText || isEditingOCR || isEditingTransformField
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

/// The ids of the dock tier on screen, reported by the row that fits.
private struct DockVisibleIDs: PreferenceKey {
    static let defaultValue: [String] = []

    static func reduce(value: inout [String], nextValue: () -> [String]) {
        value += nextValue()
    }
}
