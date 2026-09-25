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
    /// Shared by the two OCR views (regions over the thumbnail, section under
    /// it): the line under the cursor, the line just copied, the reveal state
    /// of a recognized secret, and whether the inline editor has the keyboard.
    @State private var ocrHoveredLine: Int?
    @State private var ocrCopiedLine: Int?
    @State private var ocrRevealSecret = false
    @State private var isEditingOCR = false

    init(
        item: ClipItem, text: String, isTextEditable: Bool,
        focus: FocusState<PanelFocus?>.Binding, addToBoard: @escaping () -> Void
    ) {
        self.item = item
        self.text = text
        self.isTextEditable = isTextEditable
        self.focus = focus
        self.addToBoard = addToBoard
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
            hero
            if ocrShowsHere {
                PeekImageTextSection(
                    item: item, hoveredLine: $ocrHoveredLine, copiedLine: $ocrCopiedLine,
                    revealSecret: $ocrRevealSecret, isEditing: $isEditingOCR)
            }
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
            if navActions.count > dockActionCount {
                secondaryActions
            }
            Spacer(minLength: 0)
            dock
        }
        .padding(GanchoTokens.Spacing.md)
        // The peek fills the column so the dock sits at the bottom edge; the
        // hero and result boxes are the parts that give way when space is short.
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
            TypeBadge(kind: item.kind, style: .pill)
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
        }
        .clipDragSource(item)
    }

    /// Source app · relative time · expiry, then the boards this clip is in.
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
            ForEach(model.boards.filter { boardIDs.contains($0.id) }.prefix(3)) { board in
                HStack(spacing: 3) {
                    BoardIdentityMark(board: board, size: 10)
                    if board.isSystem {
                        Text("Favorites")
                    } else {
                        Text(verbatim: board.name)
                    }
                }
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
                .accessibilityElement(children: .combine)
            }
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
        /// A shorter label for the dock's narrow buttons; nil uses `title`.
        var shortTitle: LocalizedStringKey?
        /// The key hint under a dock button. Dock actions have one; the Dev
        /// Action chips don't.
        var shortcut: String?
        let run: () -> Void
    }

    /// Paste variants first (the common case), then OCR, Pin and Board — the
    /// dock — and after those the per-kind Dev Actions as chips. Smart Paste
    /// keeps its own menu (it is async and has a language submenu).
    private var navActions: [PeekAction] {
        var actions: [PeekAction] = [
            PeekAction(
                id: "preview-paste", title: "Paste", symbol: "doc.on.clipboard", shortcut: "⏎"
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

}

// MARK: - Hero

extension ClipPeek {
    /// The kind-aware hero card: the image with its Live-Text regions, a link's
    /// host and path set large (parsed locally, never fetched), a colour band,
    /// or the (syntax-tinted) text. The card takes a wash of the kind's tint.
    private var hero: some View {
        let tint = GanchoTokens.Palette.kindTint(for: item.kind)
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.lg, style: .continuous)
        return VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            if let parts = linkParts {
                linkHero(parts)
            }
            heroBody
        }
        .padding(GanchoTokens.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            shape.fill(.quaternary.opacity(0.35))
            shape.fill(
                RadialGradient(
                    colors: [tint.opacity(0.2), .clear], center: .topLeading,
                    startRadius: 0, endRadius: 360))
        }
        .overlay(
            shape.strokeBorder(.separator.opacity(0.6), lineWidth: GanchoTokens.Stroke.hairline)
        )
        .accessibilityIdentifier("peek-hero")
    }

    /// Non-nil only when a link clip's text really parses as a URL with a
    /// host; a `url`-kind clip whose text doesn't (synthetic or edited) keeps
    /// the plain body.
    private var linkParts: ClipLinkParts? {
        guard item.kind == .url, !ClipSafePresentation.requiresMasking(item) else { return nil }
        return ClipLinkParts(text: presentedText)
    }

    @ViewBuilder private var heroBody: some View {
        if item.kind == .image, !item.isSensitive,
            let thumbnail = model.thumbnails.cached(for: item.id)
        {
            thumbnail
                .resizable()
                .scaledToFit()
                // Live Text, Gancho style: recognized lines become regions on the
                // thumbnail. The overlay sits BEFORE the frame so it takes the
                // image's fitted size, which is what the normalized boxes map to.
                .overlay {
                    PeekImageTextRegions(
                        item: item, hoveredLine: $ocrHoveredLine, copiedLine: $ocrCopiedLine,
                        revealSecret: $ocrRevealSecret)
                }
                .frame(maxWidth: .infinity, maxHeight: 240)
                .clipShape(
                    RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
                )
                // Dragging the preview itself hands the full-resolution image
                // (not the thumbnail) to the drop target.
                .clipDragSource(item)
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
        } else if item.kind == .color, !item.isSensitive,
            let color = Color(hexString: presentedText)
        {
            VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
                RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
                    .fill(color)
                    .frame(height: 72)
                    .overlay(
                        RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
                            .strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline))
                Text(presentedText).font(.body.monospaced()).textSelection(.enabled)
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

    /// Host set large, path underneath. No favicon and no metadata fetch: the
    /// copied URL never leaves the Mac to be rendered.
    private func linkHero(_ parts: ClipLinkParts) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: parts.host)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if !parts.path.isEmpty {
                Text(verbatim: parts.path)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("peek-link-hero")
    }
}

// MARK: - Action dock and chips

extension ClipPeek {
    /// Dock actions come first in `navActions` and all carry a key hint.
    private var dockActionCount: Int { navActions.filter { $0.shortcut != nil }.count }

    /// The action dock: Paste is always the prominent button (Return runs it);
    /// the keyboard-focused one — only while the peek owns the keyboard —
    /// takes a ring, so the list and the peek never look "both selected".
    private var dock: some View {
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.lg, style: .continuous)
        return HStack(spacing: GanchoTokens.Spacing.xxs) {
            ForEach(Array(navActions.prefix(dockActionCount).enumerated()), id: \.element.id) {
                index, action in
                dockButton(action, index: index)
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

    private func dockButton(_ action: PeekAction, index: Int) -> some View {
        let isPrimary = index == 0
        let isFocused = focus.wrappedValue == .peek && index == actionIndex
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
        return VStack(spacing: 3) {
            Image(systemName: action.symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(height: 18)
            Text(action.shortTitle ?? action.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(verbatim: action.shortcut ?? "")
                .font(.caption2.monospaced())
                .opacity(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(
            isPrimary
                ? AnyShapeStyle(GanchoTokens.Palette.accent)
                : isFocused
                    ? AnyShapeStyle(GanchoTokens.Palette.accent.opacity(0.18))
                    : AnyShapeStyle(.clear),
            in: shape
        )
        .foregroundStyle(isPrimary ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
        .overlay(
            shape.strokeBorder(
                isFocused ? AnyShapeStyle(.primary) : AnyShapeStyle(.clear),
                lineWidth: GanchoTokens.Stroke.focus)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            actionIndex = index
            action.run()
        }
        .help(action.title)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(action.title))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(action.id)
    }

    /// The Dev Actions as chips that wrap, bounded so a code clip's dozen
    /// transforms can't push the dock out of the panel; the keyboard focus
    /// scrolls into view.
    private var secondaryActions: some View {
        ScrollViewReader { proxy in
            ScrollView {
                FlowLayout(spacing: GanchoTokens.Spacing.xxs) {
                    ForEach(
                        Array(navActions.enumerated().dropFirst(dockActionCount)),
                        id: \.element.id
                    ) { index, action in
                        actionChip(action, index: index)
                    }
                }
            }
            .frame(maxHeight: 96)
            .onChange(of: actionIndex) { _, new in
                guard navActions.indices.contains(new) else { return }
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(navActions[new].id, anchor: .center)
                }
            }
        }
    }

    private func actionChip(_ action: PeekAction, index: Int) -> some View {
        let isFocused = focus.wrappedValue == .peek && index == actionIndex
        return HStack(spacing: 4) {
            Image(systemName: action.symbol).font(.caption2)
            Text(action.title).font(.caption.weight(.medium)).lineLimit(1)
        }
        .padding(.horizontal, GanchoTokens.Spacing.xs)
        .padding(.vertical, 4)
        .background(
            isFocused
                ? AnyShapeStyle(GanchoTokens.Palette.accent.opacity(0.18))
                : AnyShapeStyle(.quaternary),
            in: Capsule()
        )
        .overlay(
            Capsule().strokeBorder(
                isFocused ? AnyShapeStyle(.primary) : AnyShapeStyle(.clear),
                lineWidth: GanchoTokens.Stroke.focus)
        )
        .contentShape(Capsule())
        .onTapGesture {
            actionIndex = index
            action.run()
        }
        .id(action.id)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(action.id)
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
                        Button(LanguageName.localized(code: code)) {
                            runTranslate(to: Locale.Language(identifier: code))
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
    /// language (via `Locale`). The CODE is what travels: the native Translation
    /// session needs it, and the service derives the English name the model
    /// fallback's prompt wants.
    private static let translateLanguageCodes = [
        "en", "es", "fr", "de", "it", "pt", "ja", "ko", "zh"
    ]
    private func runTranslate(to target: Locale.Language) {
        actionResult = nil
        isThinking = true
        Task {
            let result = await model.smartTranslate(presentedText, to: target)
            isThinking = false
            actionResult = result ?? String(localized: "Couldn’t run that — try again.")
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
