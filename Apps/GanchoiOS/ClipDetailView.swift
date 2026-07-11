import ClipboardCore
import GanchoAI
import GanchoDesign
import GanchoKit
import GanchoSync
import GanchoTelemetry
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WidgetKit

/// Full-screen, pinch-zoomable view of an image clip — the in-list preview caps
/// at 340pt, too small to read a screenshot's text. Loads the full image (not
/// the thumbnail) so zooming stays sharp.
struct FullScreenImageView: View {
    @Environment(IOSAppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: ClipItem
    @State private var image: Image?

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    ZoomableImageView(image: image)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            if case .binary(let data, _)? = try? await model.store.content(for: item.id),
                let uiImage = UIImage(data: data)
            {
                image = Image(uiImage: uiImage)
            }
        }
    }
}

/// Pinch + double-tap zoom over a static image. Plain SwiftUI gestures keep it
/// dependency-free; double-tap toggles a 2.5× zoom for one-handed reading.
private struct ZoomableImageView: View {
    let image: Image
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        image
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .gesture(
                MagnifyGesture()
                    .onChanged { scale = max(1, min(6, lastScale * $0.magnification)) }
                    .onEnded { _ in lastScale = scale }
            )
            .onTapGesture(count: 2) {
                withAnimation(.snappy) {
                    scale = scale > 1 ? 1 : 2.5
                    lastScale = scale
                }
            }
    }
}

/// Per-kind detail: full content, dev actions, one-tap copy with haptics.
struct ClipDetailView: View {
    @Environment(IOSAppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: ClipItem
    @State private var fullText = ""
    @State private var actionResult: String?
    @State private var boardIDs: Set<UUID> = []
    @State private var smartResult: String?
    @State private var isThinking = false
    /// Sensitive clips stay masked until the user taps Reveal (the design's
    /// secret peek); never auto-revealed.
    @State private var revealed = false
    /// Whether the move-to-board sheet (the compact "Add to board") is open.
    @State private var showMoveSheet = false
    /// Whether the tapped image is open full-screen for pinch-zoom (screenshots
    /// are often small text the 340pt preview can't make legible).
    @State private var showFullImage = false
    /// The board auto-board thinks this clip belongs to (a suggestion, never
    /// auto-filed); nil until computed or once accepted/dismissed.
    @State private var suggestedBoard: Pinboard?

    /// Text-like clips (not image / file / colour) — what snippets, Smart Paste
    /// and most dev actions apply to.
    private var isTextLike: Bool {
        item.kind != .image && item.kind != .fileReference && item.kind != .color
    }

    /// Smart Paste fits text clips only and never a masked secret. Model-backed
    /// rewrites need Apple Intelligence, but deterministic PII redaction remains
    /// available whenever the user kept the Smart Paste toggle on.
    private var canSmartPaste: Bool {
        model.smartPasteAvailable && !item.isSensitive && isTextLike
    }

    /// The boards this clip currently belongs to — shown as chips in the peek.
    private var currentBoards: [Pinboard] {
        model.boards.filter { boardIDs.contains($0.id) }
    }

    /// Text handed to the iOS share sheet — the full text once loaded, else the
    /// stored preview (sensitive clips share only their masked preview).
    private var shareText: String {
        item.isSensitive ? item.preview : (fullText.isEmpty ? item.preview : fullText)
    }

    /// The medium-detent quick actions (the peek's action row). Copy is primary
    /// — iOS can't paste into another app, so copy-then-the-user-pastes is the
    /// realizable path. Smart Paste and board membership live in the sections
    /// below, revealed when the sheet is dragged to its large detent.
    @ViewBuilder private var actionRow: some View {
        HStack(spacing: 10) {
            peekAction("Copy", systemImage: "doc.on.clipboard", primary: true) {
                Task { await model.copyToPasteboard(item) }
                dismiss()
            }
            ShareLink(item: shareText) {
                peekActionLabel("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            peekAction(
                item.isPinned ? "Pinned" : "Pin",
                systemImage: item.isPinned ? "pin.fill" : "pin"
            ) {
                Task { await model.togglePin(item) }
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
    }

    private func peekAction(
        _ title: LocalizedStringKey, systemImage: String, primary: Bool = false,
        _ run: @escaping () -> Void
    ) -> some View {
        Button(action: run) { peekActionLabel(title, systemImage: systemImage, primary: primary) }
            .buttonStyle(.plain)
    }

    private func peekActionLabel(
        _ title: LocalizedStringKey, systemImage: String, primary: Bool = false
    ) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 20))
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(
                    primary
                        ? AnyShapeStyle(GanchoTokens.Palette.accent) : AnyShapeStyle(.quaternary),
                    in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
                )
                .foregroundStyle(primary ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    var body: some View {
        List {
            actionRow
            contentSection
            metaChipsSection
            boardsSection
            if isTextLike, !item.isSensitive {
                Section {
                    Button("Save as snippet", systemImage: "textformat") {
                        Task { await model.saveAsSnippet(item) }
                    }
                    .accessibilityIdentifier("detail-save-snippet")
                }
            }
            smartActionsSection
        }
        .navigationTitle(Text(LocalizedStringKey(item.kind.rawValue)))
        .sheet(isPresented: $showMoveSheet) {
            MoveToBoardSheet(item: item)
        }
        .fullScreenCover(isPresented: $showFullImage) {
            FullScreenImageView(item: item).environment(model)
        }
        .onChange(of: showMoveSheet) { _, open in
            if !open {
                Task { boardIDs = await model.boardMembership(for: item) }
            }
        }
        .task {
            if case .text(let text)? = try? await model.store.content(for: item.id) {
                fullText = text
            }
        }
        .task { await model.thumbnails.ensureLoaded(item) }
        .task {
            await model.refreshBoards()
            boardIDs = await model.boardMembership(for: item)
        }
        .task { suggestedBoard = await model.suggestedBoard(for: item) }
        // Presented as a peek: medium shows the preview + action row; drag up to
        // the large detent for chips, boards, Smart Actions, and the full text.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// The clip itself — image, text, or a masked secret kept behind Reveal.
    @ViewBuilder private var contentSection: some View {
        Section {
            if item.kind == .image, !item.isSensitive,
                let thumbnail = model.thumbnails.cached(for: item.id)
            {
                thumbnail
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 340, alignment: .center)
                    .clipShape(
                        RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { showFullImage = true }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(Text("Open full screen to zoom"))
            } else if item.isSensitive, !revealed {
                Text(item.preview)
                    .font(item.kind == .code ? .body.monospaced() : .body)
                    .foregroundStyle(.secondary)
                Button("Reveal", systemImage: "eye") { revealed = true }
                    .accessibilityIdentifier("detail-reveal")
            } else {
                // A very long Text inside a List row fails to lay out on iOS
                // (the detail came up blank). Cap what we render; the whole clip
                // is still available via Copy.
                let body = fullText.isEmpty ? item.preview : fullText
                Text(body.count > 8000 ? String(body.prefix(8000)) + "\n…" : body)
                    .font(item.kind == .code ? .body.monospaced() : .body)
                    .textSelection(.enabled)
                if item.isSensitive {
                    Button("Hide", systemImage: "eye.slash") { revealed = false }
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Provenance at a glance — kind, masked badge, source app, source device.
    @ViewBuilder private var metaChipsSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: GanchoTokens.Spacing.xs) {
                    metaChip(
                        Text(LocalizedStringKey(item.kind.rawValue)),
                        systemImage: item.kind.symbolName)
                    if item.isSensitive {
                        metaChip(Text("Masked"), systemImage: "lock.fill")
                    }
                    if let bundleID = item.sourceAppBundleID, !bundleID.isEmpty {
                        metaChip(
                            Text(verbatim: SourceApp.fallbackName(forBundleID: bundleID)),
                            systemImage: "app.dashed")
                    }
                    if let device = item.sourceDeviceName, !device.isEmpty {
                        metaChip(Text(verbatim: device), systemImage: "desktopcomputer")
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    private func metaChip(_ text: Text, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).font(.caption2)
            text.font(.caption)
        }
        .padding(.horizontal, GanchoTokens.Spacing.sm)
        .padding(.vertical, 5)
        .background(.quaternary, in: Capsule())
        .foregroundStyle(.secondary)
    }

    /// Compact board membership: the auto-board suggestion, the boards this clip
    /// is already in as chips, and one "Add to board" that opens the move sheet.
    @ViewBuilder private var boardsSection: some View {
        if let board = suggestedBoard {
            Section {
                HStack(spacing: GanchoTokens.Spacing.xs) {
                    Image(systemName: "sparkles").foregroundStyle(GanchoTokens.Palette.accent)
                    Text("Add to \(board.name)?").lineLimit(1)
                    Spacer(minLength: 0)
                    Button("Add") {
                        Task {
                            guard await model.setBoardMembership(item, board: board, member: true)
                            else { return }
                            boardIDs = await model.boardMembership(for: item)
                            suggestedBoard = nil
                        }
                    }
                    .buttonStyle(.borderless)
                    Button {
                        suggestedBoard = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain).foregroundStyle(.tertiary)
                    .accessibilityLabel(Text("Dismiss"))
                }
            }
            .accessibilityIdentifier("board-suggestion")
        }
        Section("Boards") {
            if !currentBoards.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: GanchoTokens.Spacing.xs) {
                        ForEach(currentBoards) { board in
                            HStack(spacing: 5) {
                                BoardDot(board: board, size: 9)
                                if board.isSystem {
                                    Text("Favorites")
                                } else {
                                    Text(verbatim: board.name)
                                }
                            }
                            .font(.caption)
                            .padding(.horizontal, GanchoTokens.Spacing.sm)
                            .padding(.vertical, 5)
                            .background(.quaternary, in: Capsule())
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
            }
            Button {
                showMoveSheet = true
            } label: {
                Label("Add to board", systemImage: "plus")
            }
            .accessibilityIdentifier("detail-add-to-board")
        }
    }

    /// The deterministic transforms fit any text-like clip and never a masked
    /// secret. Deliberately NO availability gate — they work on every device,
    /// with Apple Intelligence off.
    private var canTransform: Bool {
        isTextLike && !item.isSensitive
    }

    /// On-device transforms: deterministic dev actions plus, when available,
    /// Apple-Intelligence Smart Paste. One section, the design's "Smart Actions".
    @ViewBuilder private var smartActionsSection: some View {
        let actions = DevActions.actions(for: item.kind)
        if !actions.isEmpty || canTransform || canSmartPaste {
            Section {
                ForEach(actions) { action in
                    Button(LocalizedStringKey(action.title)) {
                        actionResult = (try? action.transform(fullText)) ?? ""
                    }
                }
                if canTransform {
                    // Pure text transforms, always on-device, always available;
                    // the result lands in the same review box + Copy flow as
                    // the dev actions. `.plainText` is the identity — omitted.
                    Menu {
                        ForEach(
                            PasteTransform.allCases.filter { $0 != .plainText }, id: \.self
                        ) { transform in
                            Button(LocalizedStringKey(transform.title)) {
                                actionResult = transform.apply(to: fullText)
                            }
                        }
                    } label: {
                        Label("Transform", systemImage: "textformat")
                    }
                    .accessibilityIdentifier("transform-menu")
                }
                if let actionResult, !actionResult.isEmpty {
                    Text(actionResult).font(.body.monospaced()).textSelection(.enabled)
                    Button("Copy result", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = actionResult
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
                if canSmartPaste {
                    // Smart Paste actions are one tap from the section instead of
                    // buried in a nested menu; Translate stays a submenu (9
                    // languages). `accessibilityIdentifier` kept for the tests.
                    ForEach(SmartPasteAction.allCases) { action in
                        if action == .redactPII || model.smartPasteModelAvailable {
                            Button {
                                runSmartPaste(action)
                            } label: {
                                Label(
                                    LocalizedStringKey(action.titleKey),
                                    systemImage: action.symbolName)
                            }
                            .disabled(isThinking)
                        }
                    }
                    if model.smartPasteModelAvailable {
                        Menu {
                            ForEach(Self.translateLanguageCodes, id: \.self) { code in
                                Button(Self.localizedLanguageName(code)) {
                                    runTranslate(to: Self.englishLanguageName(code))
                                }
                            }
                        } label: {
                            Label("Translate to", systemImage: "globe")
                        }
                        .disabled(isThinking)
                        .accessibilityIdentifier("smart-paste-menu")
                    }
                }
                if isThinking {
                    Label("Thinking…", systemImage: "sparkles").foregroundStyle(.secondary)
                } else if let smartResult, !smartResult.isEmpty {
                    Text(smartResult).font(.body).textSelection(.enabled)
                    Button("Copy result", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = smartResult
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
            } header: {
                HStack {
                    Text("Smart Actions")
                    Spacer()
                    Text("on-device").foregroundStyle(.tertiary)
                }
                .textCase(nil)
            }
        }
    }

    private static let translateLanguageCodes = [
        "en", "es", "fr", "de", "it", "pt", "ja", "ko", "zh"
    ]
    private static func localizedLanguageName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code
    }
    private static func englishLanguageName(_ code: String) -> String {
        Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code
    }

    private func runSmartPaste(_ action: SmartPasteAction) {
        smartResult = nil
        isThinking = true
        Task {
            let result = await model.smartPaste(fullText, action: action)
            isThinking = false
            smartResult = result ?? String(localized: "Couldn’t run that — try again.")
        }
    }

    private func runTranslate(to language: String) {
        smartResult = nil
        isThinking = true
        Task {
            let result = await model.smartTranslate(fullText, to: language)
            isThinking = false
            smartResult = result ?? String(localized: "Couldn’t run that — try again.")
        }
    }
}
