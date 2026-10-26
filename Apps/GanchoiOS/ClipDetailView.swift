import ClipboardCore
import GanchoAI
import GanchoAppCore
import GanchoDesign
import GanchoKit
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
                withAnimation(GanchoMotion.quick(reduceMotion: GanchoMotion.systemReducesMotion)) {
                    scale = scale > 1 ? 1 : 2.5
                    lastScale = scale
                }
            }
    }
}

/// Per-kind detail, Copy first: provenance, the title, the content (a link as
/// its hero), one full-width Copy, then Share · Pin · Board · Snippet, smart
/// actions as chips, and the boards it is on.
struct ClipDetailView: View {
    @Environment(IOSAppModel.self) var model
    @Environment(\.dismiss) var dismiss
    let item: ClipItem
    /// Shows ⌘⏎ on Copy where a hardware keyboard can press it.
    var showsCopyShortcut = false
    @State var fullText = ""
    @State var hasLoadedFullText = false
    /// Non-nil only when the durable payload is plain text and policy permits
    /// editing. Binary/rich/file/sensitive rows remain read-only.
    @State var editableText: String?
    @State var actionResult: String?
    @State var boardIDs: Set<UUID> = []
    @State var smartResult: String?
    @Environment(\.scenePhase) private var scenePhase
    @State var translationTargets: [TranslationDestination] = []
    @State var translationFailed = false
    @State var translationRefresh = 0
    @State var translationTask: Task<Void, Never>?
    @State var translationRequestID = UUID()
    @State var isThinking = false
    /// Sensitive clips stay masked until the user taps Reveal (the design's
    /// secret peek); never auto-revealed.
    @State var revealed = false
    /// Whether the move-to-board sheet (Board, or + Add) is open.
    @State var showMoveSheet = false
    /// Whether the tapped image is open full-screen for pinch-zoom (screenshots
    /// are often small text the 340pt preview can't make legible).
    @State var showFullImage = false
    /// The board auto-board thinks this clip belongs to (a suggestion, never
    /// auto-filed); nil until computed or once accepted/dismissed.
    @State var suggestedBoard: Pinboard?
    /// Whether this clip is already a snippet, for the Snippet button's state.
    @State var isSnippet = false
    /// A link shows as its hero until the user asks to edit its text.
    @State var editingLink = false

    /// Text-like clips (not image / file / colour) — what snippets, Smart Paste
    /// and most dev actions apply to.
    var isTextLike: Bool {
        item.kind != .image && item.kind != .fileReference && item.kind != .color
    }

    /// Includes malformed legacy/sync rows whose kind is intrinsically masked
    /// even when their `isSensitive` metadata is false.
    var requiresMasking: Bool {
        ClipSafePresentation.requiresMasking(item)
    }

    /// Smart Paste fits text clips only and never a masked secret. Model-backed
    /// rewrites need Apple Intelligence, but deterministic PII redaction remains
    /// available whenever the user kept the Smart Paste toggle on.
    var canSmartPaste: Bool {
        model.smartPasteAvailable && hasLoadedFullText && !requiresMasking && isTextLike
    }

    /// The boards this clip currently belongs to — shown as chips in the peek.
    var currentBoards: [Pinboard] {
        model.boards.filter { boardIDs.contains($0.id) }
    }

    /// A link that isn't masked shows as its hero instead of a text block.
    var linkParts: ClipLinkParts? {
        item.kind == .url && !requiresMasking
            ? ClipLinkParts(text: fullText.isEmpty ? item.preview : fullText) : nil
    }

    var body: some View {
        List {
            provenanceRow
            ClipTitleEditor(title: item.title, prominent: true) { title in
                await model.updateClipTitle(item, title: title)
            }
            .id(item.id)
            if let linkParts, !editingLink {
                linkHero(linkParts)
            } else if editableText != nil {
                ClipTextEditor(
                    text: editableTextBinding, kind: item.kind, startsEditing: editingLink
                ) { text in
                    let saved = await model.updateClipText(item, text: text)
                    if saved { editingLink = false }
                    return saved
                }
                .id(item.id)
            } else {
                contentSection
            }
            actionsSection
            smartActionsSection
            boardsSection
        }
        .listSectionSpacing(.compact)
        .navigationTitle(Text(verbatim: ""))
        .navigationBarTitleDisplayMode(.inline)
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
        .task(id: translationAvailabilityRequest) { await refreshTranslationTargets() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { translationRefresh += 1 }
        }
        .onDisappear { translationTask?.cancel() }
        .onChange(of: fullText) { _, _ in
            translationTargets = []
            translationTask?.cancel()
            translationRequestID = UUID()
            isThinking = false
            translationFailed = false
        }
        // Call sites also reset identity with `.id(item.id)`; this keeps a
        // revealed secret or a draft from carrying over if one ever doesn't.
        .onChange(of: item.id) { _, _ in
            revealed = false
            editableText = nil
            actionResult = nil
            smartResult = nil
        }
        .task(id: ContentRequest(clipID: item.id, revealed: revealed)) {
            let store = model.store
            let payload = await ClipPreviewLoader().load(
                item, revealMaskedContent: revealed
            ) { id in
                try await store.content(for: id)
            }
            guard !Task.isCancelled else { return }
            switch payload {
            case .text(let text):
                fullText = text
                hasLoadedFullText = true
                if !requiresMasking, item.kind.allowsTextEditing {
                    editableText = text
                }
            case .masked, .binary, .fileReferences, .unavailable:
                fullText = ""
                hasLoadedFullText = false
                editableText = nil
            }
        }
        .task(id: ClipContentVersion(item)) { await model.detailImages.ensureLoaded(item) }
        .task(id: item.id) {
            await model.refreshBoards()
            boardIDs = await model.boardMembership(for: item)
        }
        .task(id: item.id) { suggestedBoard = await model.suggestedBoard(for: item) }
        .task(id: item.id) { isSnippet = await model.isSnippet(item) }
        // Presented as a peek: medium shows provenance, the title, the content
        // and Copy; drag up to the large detent for actions and boards.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var editableTextBinding: Binding<String> {
        Binding(
            get: { editableText ?? fullText },
            set: { newText in
                editableText = newText
                fullText = newText
            })
    }

    /// The clip itself — image, text, or a masked secret kept behind Reveal.
    @ViewBuilder private var contentSection: some View {
        Section {
            if item.kind == .image, !requiresMasking,
                let thumbnail = model.detailImages.cached(for: item)
                    ?? model.thumbnails.cached(for: item)
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
            } else if requiresMasking, !revealed {
                Text(ClipSafePresentation.masked)
                    .font(item.kind == .code ? .body.monospaced() : .body)
                    .foregroundStyle(.secondary)
                Button("Reveal", systemImage: "eye") { revealed = true }
                    .accessibilityIdentifier("detail-reveal")
            } else if requiresMasking, !hasLoadedFullText {
                ProgressView()
                Button("Hide", systemImage: "eye.slash") { revealed = false }
                    .foregroundStyle(.secondary)
            } else {
                // A very long Text inside a List row fails to lay out on iOS
                // (the detail came up blank). Cap what we render; the whole clip
                // is still available via Copy.
                let fallback = requiresMasking ? ClipSafePresentation.masked : item.preview
                let body = fullText.isEmpty ? fallback : fullText
                Text(ClipTextPreview.truncated(body, limit: 8_000))
                    .font(item.kind == .code ? .body.monospaced() : .body)
                    .textSelection(.enabled)
                if requiresMasking {
                    Button("Hide", systemImage: "eye.slash") {
                        fullText = ""
                        hasLoadedFullText = false
                        revealed = false
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// What the detail's content load depends on: a new clip or a reveal toggle.
private struct ContentRequest: Hashable {
    let clipID: UUID
    let revealed: Bool
}
