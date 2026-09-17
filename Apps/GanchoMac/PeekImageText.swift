import ClipboardCore
import GanchoAI
import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// The vocabulary the two OCR views share: what "masked" means and how the
/// line under the cursor gets copied. Both render ONE `ManualOCRSession`, the
/// regions over the thumbnail and the section under it, so hover, the copied
/// line and the reveal state live in `ClipPeek` and arrive here as bindings.
@MainActor
enum PeekImageText {
    /// A flagged secret stays masked until the user reveals it — the contract
    /// sensitive clips already have everywhere else in Gancho.
    static func isMasked(_ session: ManualOCRSession, revealed: Bool) -> Bool {
        session.isSensitive && !revealed
    }

    static func tint(masked: Bool) -> Color {
        masked ? GanchoTokens.Palette.danger : GanchoTokens.Palette.accent
    }

    /// A click on a region or a row: reveal first when masked, otherwise copy
    /// that one line after the same revalidation the review window applies.
    static func copyLine(
        _ index: Int, model: AppModel, revealSecret: Binding<Bool>, copiedLine: Binding<Int?>
    ) {
        let session = model.manualOCR
        guard session.lines.indices.contains(index) else { return }
        if isMasked(session, revealed: revealSecret.wrappedValue) {
            revealSecret.wrappedValue = true
            return
        }
        let text = session.lines[index].text
        Task {
            guard await model.copyManualText(text) else { return }
            withAnimation { copiedLine.wrappedValue = index }
            try? await Task.sleep(for: .seconds(1.2))
            if copiedLine.wrappedValue == index {
                withAnimation { copiedLine.wrappedValue = nil }
            }
        }
    }
}

/// Live Text, Gancho style: each recognized line is a region over the
/// thumbnail. Hover mirrors the row in the section; a click copies that line.
struct PeekImageTextRegions: View {
    let item: ClipItem
    @Binding var hoveredLine: Int?
    @Binding var copiedLine: Int?
    @Binding var revealSecret: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        let session = model.manualOCR
        if session.itemID == item.id, session.lines.contains(where: { $0.box != nil }) {
            let masked = PeekImageText.isMasked(session, revealed: revealSecret)
            let tint = PeekImageText.tint(masked: masked)
            GeometryReader { proxy in
                ForEach(Array(session.lines.enumerated()), id: \.offset) { index, line in
                    if let box = line.box {
                        region(
                            box, in: proxy.size, index: index, line: line, masked: masked,
                            tint: tint)
                    }
                }
            }
        }
    }

    private func region(
        _ box: CGRect, in size: CGSize, index: Int, line: RecognizedTextLine, masked: Bool,
        tint: Color
    ) -> some View {
        let rect = CGRect(
            x: box.minX * size.width, y: box.minY * size.height,
            width: box.width * size.width, height: box.height * size.height
        ).insetBy(dx: -3, dy: -2)
        let isHovered = hoveredLine == index
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(tint.opacity(isHovered ? 0.34 : 0.2))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(
                        tint.opacity(isHovered ? 1 : 0.55),
                        lineWidth: isHovered
                            ? GanchoTokens.Stroke.focus : GanchoTokens.Stroke.hairline)
            )
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .onHover { inside in
                if inside {
                    hoveredLine = index
                } else if hoveredLine == index {
                    hoveredLine = nil
                }
            }
            .onTapGesture {
                PeekImageText.copyLine(
                    index, model: model, revealSecret: $revealSecret, copiedLine: $copiedLine)
            }
            .accessibilityElement()
            .accessibilityLabel(masked ? Text("Reveal") : Text("Copy line"))
            .accessibilityValue(Text(verbatim: masked ? "" : line.text))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("peek-ocr-region-\(index)")
    }
}

/// The recognized text lives HERE, beside the image it came from, at the same
/// body size as every other clip — not in a toast and not in a detached
/// window. Every state renders in place.
struct PeekImageTextSection: View {
    let item: ClipItem
    @Binding var hoveredLine: Int?
    @Binding var copiedLine: Int?
    @Binding var revealSecret: Bool
    /// Owned by the peek: while the inline editor has the keyboard, the peek's
    /// arrow/Return handling must stand aside.
    @Binding var isEditing: Bool
    @Environment(AppModel.self) private var model
    @State private var copiedAll = false
    @State private var draft = ""
    /// Entity chips: what the recognized text can DO, computed from the text
    /// itself and never shown for a masked secret.
    @State private var entities: [ImageTextEntity] = []
    /// One value for the whole translation lifecycle, so the states that must
    /// not coexist cannot: a finished translation keeps its target, and a
    /// refresh of the offer never erases it.
    @State private var translation: TranslationState = .none
    @State private var translationTask: Task<Void, Never>?
    @State private var translationCopied = false

    enum TranslationState: Equatable {
        case none
        case offered(Locale.Language)
        case running(Locale.Language)
        case done(Locale.Language, String)
        case failed(Locale.Language)

        var target: Locale.Language? {
            switch self {
            case .none: nil
            case .offered(let t), .running(let t), .done(let t, _), .failed(let t): t
            }
        }
        /// A result on screen or in flight survives an offer refresh.
        var isSettled: Bool {
            switch self {
            case .running, .done: true
            default: false
            }
        }
    }

    private var session: ManualOCRSession { model.manualOCR }
    private var masked: Bool { PeekImageText.isMasked(session, revealed: revealSecret) }
    private var tint: Color { PeekImageText.tint(masked: masked) }
    /// Recognized code reads better in the monospaced face code clips use.
    private var isCode: Bool { RuleClassifier().classify(session.text) == .code }

    var body: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            HStack(spacing: GanchoTokens.Spacing.xs) {
                Text("Text in image")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer(minLength: 0)
                status
            }
            switch session.state {
            case .recognizing:
                skeleton
            case .noText:
                Text("No readable text found").foregroundStyle(.secondary)
            case .unavailable:
                Text("Image is no longer available for OCR").foregroundStyle(.secondary)
            case .failed:
                Text("Couldn’t read this image. Try another image.").foregroundStyle(.secondary)
            case .copied, .ready:
                if isEditing {
                    editor
                } else {
                    lines
                    entityChips
                    translationBlock
                    actions
                }
            case .idle:
                EmptyView()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("peek-ocr")
        // A new request (same clip, run again) starts from a clean section.
        .onChange(of: session.requestID) { _, _ in
            copiedAll = false
            isEditing = false
            cancelTranslation()
        }
        .onDisappear { cancelTranslation() }
        .task(id: "\(session.requestID)|\(session.state)|\(session.isSensitive)") {
            await refreshOffers()
        }
    }

    @ViewBuilder private var status: some View {
        switch session.state {
        case .recognizing:
            HStack(spacing: GanchoTokens.Spacing.xs) {
                ProgressView().controlSize(.mini)
                Text("Recognizing text…")
                Button("Cancel") { session.cancel() }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("peek-ocr-cancel")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        case .copied,
            .ready where copiedAll:
            Label("Copied to clipboard", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(GanchoTokens.Palette.success)
                // ONE element whose label is the text: an id on the Label alone
                // propagates to the icon child, and a test's firstMatch lands there.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Copied to clipboard"))
                .accessibilityIdentifier("peek-ocr-status")
        case .ready where session.isSensitive:
            Label("Contains a secret", systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(GanchoTokens.Palette.danger)
                // ONE element whose label is the text: an id on the Label alone
                // propagates to the icon child, and a test's firstMatch lands there.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Contains a secret"))
                .accessibilityIdentifier("peek-ocr-status")
        case .ready:
            Label("Clipboard unchanged", systemImage: "doc.on.clipboard")
                .font(.caption)
                .foregroundStyle(.secondary)
                // ONE element whose label is the text: an id on the Label alone
                // propagates to the icon child, and a test's firstMatch lands there.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Clipboard unchanged"))
                .accessibilityIdentifier("peek-ocr-status")
        default:
            EmptyView()
        }
    }

    /// Placeholder rows while Vision works, in the rhythm the lines will take,
    /// so the section does not jump when the text lands.
    private var skeleton: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            ForEach([72, 128, 176], id: \.self) { trailing in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.quaternary)
                    .frame(height: 12)
                    .padding(.trailing, CGFloat(trailing))
            }
        }
        .accessibilityHidden(true)
    }

    private var lines: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(session.lines.enumerated()), id: \.offset) { index, line in
                let shown = masked ? SensitiveMasking.maskedPreview(for: line.text) : line.text
                HStack(spacing: GanchoTokens.Spacing.xs) {
                    Text(verbatim: shown)
                        .font(isCode ? .body.monospaced() : .body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if copiedLine == index {
                        Label("Line copied", systemImage: "checkmark")
                            .font(.caption)
                            .foregroundStyle(GanchoTokens.Palette.success)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    hoveredLine == index ? tint.opacity(0.14) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                )
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside {
                        hoveredLine = index
                    } else if hoveredLine == index {
                        hoveredLine = nil
                    }
                }
                .onTapGesture {
                    PeekImageText.copyLine(
                        index, model: model, revealSecret: $revealSecret, copiedLine: $copiedLine)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: shown))
                .accessibilityHint(masked ? Text("Reveal") : Text("Copy line"))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("peek-ocr-line-\(index)")
            }
        }
        // A container boundary, or this id would overwrite every row's own id.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("peek-ocr-text")
    }

    private var actions: some View {
        fitting {
            if masked {
                ActionButton("Reveal", systemImage: "eye", identifier: "peek-ocr-reveal") {
                    revealSecret = true
                }
            } else {
                ActionButton("Copy all", systemImage: "doc.on.doc", identifier: "peek-ocr-copy") {
                    Task { await copyAll() }
                }
                ActionButton(
                    "Save as clip", systemImage: "square.and.arrow.down",
                    identifier: "peek-ocr-save"
                ) {
                    Task { await save(session.text) }
                }
                ActionButton("Edit", systemImage: "pencil", identifier: "peek-ocr-edit") {
                    draft = session.text
                    isEditing = true
                }
                if session.isSensitive {
                    ActionButton("Hide", systemImage: "eye.slash", identifier: "peek-ocr-hide") {
                        revealSecret = false
                    }
                }
            }
        }
    }

    /// Edits stay in the peek and stay transient until Copy or Save.
    private var editor: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            TextEditor(text: $draft)
                .font(isCode ? .body.monospaced() : .body)
                .scrollContentBackground(.hidden)
                .padding(GanchoTokens.Spacing.xxs)
                // Short on purpose: the editor shares the peek with the image and the
                // action list, and a tall editor squeezes the thumbnail.
                .frame(minHeight: 72, maxHeight: 120)
                .background(
                    .quaternary.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
                )
                .accessibilityIdentifier("peek-ocr-editor")
            fitting {
                ActionButton(
                    "Copy text", systemImage: "doc.on.doc", identifier: "peek-ocr-editor-copy"
                ) {
                    Task {
                        if await model.copyManualText(draft) {
                            copiedAll = true
                            isEditing = false
                        }
                    }
                }
                ActionButton(
                    "Save as clip", systemImage: "square.and.arrow.down",
                    identifier: "peek-ocr-editor-save"
                ) {
                    Task {
                        if await save(draft) { isEditing = false }
                    }
                }
                ActionButton("Cancel", systemImage: "xmark", identifier: "peek-ocr-editor-cancel") {
                    isEditing = false
                }
            }
        }
    }

    /// Buttons in a row while they fit, stacked when the peek (or the language)
    /// is narrow: a truncated "Save as cl…" is never acceptable here.
    private func fitting<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: GanchoTokens.Spacing.xxs) { content() }
            VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xxs) { content() }
        }
    }

    private func copyAll() async {
        guard await model.copyManualText(session.text) else { return }
        withAnimation { copiedAll = true }
    }

    @discardableResult
    private func save(_ text: String) async -> Bool {
        guard let validated = await session.reviewedText(text) else { return false }
        return await model.saveManualText(validated)
    }
}

// MARK: - Entity chips and translation

extension PeekImageTextSection {
    // MARK: - Entity chips

    /// Links, emails and Translate, from the recognized text itself. Chips wrap
    /// instead of truncating, and none appears for a secret: a flagged text is
    /// never sent anywhere, not even to the on-device model.
    @ViewBuilder private var entityChips: some View {
        if !session.isSensitive, !entities.isEmpty || translation.target != nil {
            FlowLayout(spacing: GanchoTokens.Spacing.xxs) {
                ForEach(Array(entities.enumerated()), id: \.offset) { index, entity in
                    switch entity {
                    case .link(let url):
                        chip(
                            Text("Open \(url.host ?? url.absoluteString)"),
                            systemImage: "arrow.up.right", identifier: "peek-ocr-link-\(index)"
                        ) { model.openRecognizedEntity(entity) }
                    case .email(let address, _):
                        // The address IS the label: two recipients must never
                        // read as the same chip, to the eye or to VoiceOver.
                        chip(
                            Text("Email \(address)"), systemImage: "envelope",
                            identifier: "peek-ocr-email-\(index)"
                        ) { model.openRecognizedEntity(entity) }
                    }
                }
                switch translation {
                case .offered(let target), .failed(let target):
                    chip(Text("Translate"), systemImage: "globe", identifier: "peek-ocr-translate")
                    {
                        translate(to: target)
                    }
                case .running:
                    chip(
                        Text("Translating…"), systemImage: "globe",
                        identifier: "peek-ocr-translating"
                    ) {}
                    .disabled(true)
                case .none, .done:
                    EmptyView()
                }
            }
            if case .failed = translation {
                Text("Couldn’t run that — try again.")
                    .font(.caption)
                    .foregroundStyle(GanchoTokens.Palette.danger)
                    .accessibilityIdentifier("peek-ocr-translation-error")
            }
        }
    }

    /// The translation reads beside the original, at the same body size, with
    /// its own Copy and Paste: the common case is "translate and paste". Both
    /// go through the same revalidation as every other copy from this section.
    @ViewBuilder private var translationBlock: some View {
        if case .done(let target, let text) = translation {
            VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
                HStack(spacing: GanchoTokens.Spacing.xs) {
                    Text("Translation")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(verbatim: LanguageName.localized(target))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    if translationCopied {
                        Label("Copied to clipboard", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(GanchoTokens.Palette.success)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text("Copied to clipboard"))
                            .accessibilityIdentifier("peek-ocr-translation-status")
                    }
                }
                // Capped like the peek's other long outputs (`resultBox`): the
                // peek column does not scroll, so an uncapped block would push
                // the action list off the panel.
                ScrollView {
                    Text(verbatim: text)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("peek-ocr-translation")
                }
                .frame(maxHeight: 140)
                fitting {
                    ActionButton(
                        "Copy translation", systemImage: "doc.on.doc",
                        identifier: "peek-ocr-translation-copy"
                    ) {
                        Task {
                            guard await model.copyManualText(text) else { return }
                            withAnimation { translationCopied = true }
                        }
                    }
                    ActionButton(
                        "Paste translation", systemImage: "doc.on.clipboard",
                        identifier: "peek-ocr-translation-paste"
                    ) {
                        Task {
                            guard let validated = await session.reviewedText(text) else { return }
                            model.pasteText(validated)
                        }
                    }
                }
            }
        }
    }

    /// 11 pt medium: the macOS floor for an interactive label, one step above
    /// the 10 pt metadata around it, so a chip reads as a control.
    private func chip(
        _ title: Text, systemImage: String, identifier: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                title
            } icon: {
                Image(systemName: systemImage)
            }
            .font(.subheadline.weight(.medium))
            // No line limit: a long host wraps inside the chip, so the full
            // destination stays readable and nothing is ever cut to a
            // trusted-looking prefix.
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                GanchoTokens.Palette.accent.opacity(0.1),
                in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    /// Recompute what the text can do whenever the result changes. Detection is
    /// synchronous and cheap; the translation offer asks the platform which
    /// engine can run, so it lands a beat later. A translation already running
    /// or on screen is left alone: the offer only fills an empty slot.
    private func refreshOffers() async {
        guard session.state == .copied || session.state == .ready, !session.isSensitive else {
            entities = []
            cancelTranslation()
            return
        }
        let request = session.requestID
        let text = session.text
        entities = ImageTextEntityDetector().entities(in: text)
        guard !translation.isSettled else { return }
        translation = .none
        guard model.smartPasteAvailable else { return }
        let target = await ImageTextTranslation.offer(
            for: text, interface: Locale.current.language,
            modelAvailable: model.smartPasteModelAvailable)
        guard !Task.isCancelled, request == session.requestID, !translation.isSettled else {
            return
        }
        translation = target.map(TranslationState.offered) ?? .none
    }

    /// Runs on the SAME revalidation as a copy: a source that stopped
    /// permitting reuse (private mode, deletion, expiry) is never sent to the
    /// model. The task is keyed to the request and cancelled with it, so a
    /// superseded translation can neither re-enable the chip nor land.
    private func translate(to target: Locale.Language) {
        translationTask?.cancel()
        translation = .running(target)
        let request = session.requestID
        translationTask = Task {
            guard let text = await session.reviewedText(session.text) else {
                if request == session.requestID { translation = .failed(target) }
                return
            }
            let result = await model.smartTranslate(text, to: target)
            guard !Task.isCancelled, request == session.requestID else { return }
            if let result, !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                translation = .done(target, result)
            } else {
                translation = .failed(target)
            }
        }
    }

    private func cancelTranslation() {
        translationTask?.cancel()
        translationTask = nil
        translation = .none
        translationCopied = false
    }
}
