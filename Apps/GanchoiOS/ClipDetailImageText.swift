import ClipboardCore
import GanchoAI
import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// How one recognized line reads, shared by its region and its row.
struct ImageTextLineStyle {
    let isHeld: Bool
    let isLink: Bool
    let isCopied: Bool

    var tint: Color {
        if isHeld { return GanchoTokens.Palette.danger }
        if isCopied { return GanchoTokens.Palette.accent }
        if isLink { return GanchoTokens.Palette.kindTint(for: .url) }
        return Color(uiColor: .systemGray)
    }

    /// The first web link on each line, found once per result.
    static func links(in lines: [RecognizedTextLine]) -> [Int: URL] {
        let detector = ImageTextEntityDetector()
        var links: [Int: URL] = [:]
        for (index, line) in lines.enumerated() {
            for case .link(let url) in detector.entities(in: line.text) {
                links[index] = url
                break
            }
        }
        return links
    }
}

/// Each recognized line as a numbered region over the image; a tap copies
/// that line, or reveals it first when it is held back.
struct ClipImageTextRegions: View {
    @Environment(IOSAppModel.self) private var model
    let item: ClipItem
    let revealed: Set<Int>
    let copiedLine: Int?
    let links: [Int: URL]
    let onLine: (Int) -> Void

    var body: some View {
        let session = model.manualOCR
        if session.itemID == item.id, session.state == .ready {
            GeometryReader { proxy in
                ForEach(Array(session.lines.enumerated()), id: \.offset) { index, line in
                    if let box = line.box {
                        region(box, in: proxy.size, index: index, line: line)
                    }
                }
            }
        }
    }

    private func region(
        _ box: CGRect, in size: CGSize, index: Int, line: RecognizedTextLine
    ) -> some View {
        let style = ImageTextLineStyle(
            isHeld: model.manualOCR.heldLines.contains(index) && !revealed.contains(index),
            isLink: links[index] != nil,
            isCopied: copiedLine == index)
        let rect = CGRect(
            x: box.minX * size.width, y: box.minY * size.height,
            width: box.width * size.width, height: box.height * size.height
        ).insetBy(dx: -4, dy: -3)
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        return
            shape
            .fill(style.tint.opacity(0.14))
            .overlay(
                shape.strokeBorder(
                    style.tint,
                    style: StrokeStyle(lineWidth: 1.5, dash: style.isHeld ? [4, 3] : []))
            )
            .overlay(alignment: .topLeading) {
                Text(verbatim: "\(index + 1)")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(style.tint, in: Circle())
                    // Pulled inside the image near an edge, where it would be clipped.
                    .offset(x: -min(8, rect.minX), y: -min(8, rect.minY))
            }
            .frame(width: rect.width, height: rect.height)
            .contentShape(shape)
            .onTapGesture { onLine(index) }
            .position(x: rect.midX, y: rect.midY)
            .accessibilityElement()
            .accessibilityLabel(Text("Line \(index + 1)"))
            .accessibilityHint(style.isHeld ? Text("Reveal") : Text("Copy line"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onLine(index) }
            .accessibilityIdentifier("detail-ocr-region-\(index + 1)")
    }
}

/// The text read from an image clip: one row per line, a held-back secret
/// behind Reveal, then Copy all · Save · Translate. Nothing is copied or
/// stored without a tap.
struct ClipImageTextSection: View {
    @Environment(IOSAppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let item: ClipItem
    @Binding var revealed: Set<Int>
    let copiedLine: Int?
    let links: [Int: URL]
    let onLine: (Int) -> Void
    @State private var translation: Translation = .none
    @State private var translationTargets: [TranslationDestination] = []
    @State private var translationTask: Task<Void, Never>?
    @State private var copiedAll = false

    enum Translation: Equatable {
        case none
        case running
        case done(String)
        case failed
    }

    private var session: ManualOCRSession { model.manualOCR }
    private var released: [Int] { session.releasedLines(revealed: revealed) }

    var body: some View {
        if session.itemID == item.id, session.state != .idle, session.state != .noText {
            Section {
                switch session.state {
                case .recognizing:
                    skeleton
                case .unavailable:
                    Text("Image is no longer available for OCR").foregroundStyle(.secondary)
                case .failed:
                    Text("Couldn’t read this image. Try another image.")
                        .foregroundStyle(.secondary)
                default:
                    ForEach(Array(session.lines.enumerated()), id: \.offset) { index, line in
                        row(index, line: line)
                    }
                    actions
                    translationResult
                }
            } header: {
                header
            }
        }
    }

    private var header: some View {
        HStack {
            if session.state == .ready {
                Text("Text in image · \(session.lines.count) lines")
            } else {
                Text("Text in image")
            }
            if session.state == .recognizing { ProgressView().controlSize(.mini) }
            Spacer()
            Label("on-device", systemImage: "lock.shield")
                .labelStyle(.titleAndIcon)
                .textCase(nil)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("detail-ocr")
        // On the header, not the Section: list rows come and go as they scroll.
        .onChange(of: session.requestID) { _, _ in resetTranslation() }
        .onChange(of: revealed) { _, _ in copiedAll = false }
        .task(id: TargetsRequest(request: session.requestID, state: session.state)) {
            await refreshTargets()
        }
    }

    /// Placeholder rows in the rhythm the lines will take, so nothing jumps.
    private var skeleton: some View {
        ForEach([96, 160, 64], id: \.self) { trailing in
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(.quaternary)
                .frame(height: 12)
                .padding(.trailing, CGFloat(trailing))
                .accessibilityHidden(true)
        }
    }

    private func row(_ index: Int, line: RecognizedTextLine) -> some View {
        let held = session.heldLines.contains(index) && !revealed.contains(index)
        let link = held ? nil : links[index]
        let shown = held ? SensitiveMasking.maskedPreview(for: line.text) : line.text
        return HStack(spacing: 8) {
            Text(verbatim: "\(index + 1)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 6)
                .frame(minWidth: 18, minHeight: 18)
                .background(.primary.opacity(0.08), in: Capsule())
                .accessibilityHidden(true)
            Text(verbatim: shown)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(
                    held ? AnyShapeStyle(GanchoTokens.Palette.danger) : AnyShapeStyle(.primary)
                )
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let link {
                Button {
                    openURL(link)
                } label: {
                    lineChip(Text("link"), tint: GanchoTokens.Palette.kindTint(for: .url))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Open \(link.host ?? link.absoluteString)"))
            }
            if held {
                lineChip(Text("contains a secret"), tint: GanchoTokens.Palette.danger)
                Button("Reveal") { onLine(index) }
                    .font(.subheadline.weight(.bold))
                    .buttonStyle(.borderless)
                    .ganchoTextButton()
                    .accessibilityIdentifier("detail-ocr-reveal-\(index + 1)")
            } else {
                Button {
                    onLine(index)
                } label: {
                    Image(systemName: copiedLine == index ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 16))
                        .foregroundStyle(GanchoTokens.Palette.accentInk)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(copiedLine == index ? Text("Line copied") : Text("Copy line"))
                .accessibilityIdentifier("detail-ocr-copy-line-\(index + 1)")
            }
        }
        .frame(minHeight: 44)
        .listRowBackground(held ? GanchoTokens.Palette.danger.opacity(0.06) : nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: shown))
        .accessibilityIdentifier("detail-ocr-line-\(index + 1)")
    }

    private func lineChip(_ title: Text, tint: Color) -> some View {
        title
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .frame(minHeight: 18)
            .foregroundStyle(ReadableInk(base: tint))
            .background(tint.opacity(0.14), in: Capsule())
            .fixedSize()
    }

    private var actions: some View {
        FlowLayout(spacing: 6) {
            Button {
                Task {
                    copiedAll = await model.copyRecognizedText(
                        session.releasedText(revealed: revealed))
                }
            } label: {
                actionLabel(
                    Text("Copy all · \(released.count)"),
                    systemImage: copiedAll ? "checkmark" : "doc.on.doc", primary: true)
            }
            .buttonStyle(.plain)
            .disabled(released.isEmpty)
            .accessibilityIdentifier("detail-ocr-copy-all")
            Button {
                Task {
                    _ = await model.saveRecognizedLines(session.releasedText(revealed: revealed))
                }
            } label: {
                actionLabel(Text("Save text as clip"), systemImage: "doc.badge.plus")
            }
            .buttonStyle(.plain)
            .disabled(released.isEmpty)
            .accessibilityIdentifier("detail-ocr-save")
            if !session.isSensitive, !translationTargets.isEmpty { translateMenu }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
    }

    /// Never offered for a result with a secret in it: flagged text is not
    /// sent anywhere, not even to the on-device model.
    private var translateMenu: some View {
        Menu {
            ForEach(translationTargets) { destination in
                Button(LanguageName.localized(code: destination.code)) {
                    translate(to: Locale.Language(identifier: destination.code))
                }
                .disabled(!destination.isAvailable)
            }
        } label: {
            actionLabel(Text("Translate"), systemImage: "globe", trailing: "chevron.down")
        }
        .tint(.primary)
        .disabled(translation == .running)
        .accessibilityIdentifier("detail-ocr-translate")
    }

    @ViewBuilder private var translationResult: some View {
        switch translation {
        case .running:
            Label("Thinking…", systemImage: "sparkles").foregroundStyle(.secondary)
        case .done(let text):
            Text(verbatim: text).textSelection(.enabled)
                .accessibilityIdentifier("detail-ocr-translation")
            Button("Copy result", systemImage: "doc.on.doc") {
                Task { _ = await model.copyRecognizedText(text) }
            }
        case .failed:
            Text("Couldn’t run that — try again.").foregroundStyle(.secondary)
        case .none:
            EmptyView()
        }
    }

    private func actionLabel(
        _ title: Text, systemImage: String, trailing: String? = nil, primary: Bool = false
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).font(.caption)
            title
            if let trailing { Image(systemName: trailing).font(.caption2) }
        }
        .font(.subheadline.weight(primary ? .semibold : .regular))
        .padding(.horizontal, GanchoTokens.Spacing.sm)
        .frame(minHeight: 30)
        .foregroundStyle(
            primary ? AnyShapeStyle(GanchoTokens.Palette.accentInk) : AnyShapeStyle(.primary)
        )
        .background(
            primary ? AnyShapeStyle(GanchoTokens.Palette.accentTint) : AnyShapeStyle(.quaternary),
            in: Capsule()
        )
        .contentShape(Capsule())
    }

    private func refreshTargets() async {
        guard session.state == .ready, !session.isSensitive, model.smartPasteAvailable else {
            translationTargets = []
            return
        }
        let request = session.requestID
        let targets = try? await model.translationDestinations(session.text)
        guard !Task.isCancelled, request == session.requestID else { return }
        translationTargets = targets ?? []
    }

    /// Checked again before it runs, like every copy from this section.
    private func translate(to target: Locale.Language) {
        translationTask?.cancel()
        translation = .running
        let request = session.requestID
        translationTask = Task {
            guard !session.isSensitive, let text = await session.reviewedText(session.text) else {
                if request == session.requestID { translation = .failed }
                return
            }
            let result = await model.smartTranslate(text, to: target)
            guard !Task.isCancelled, request == session.requestID else { return }
            if let result, !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                translation = .done(result)
            } else {
                translation = .failed
            }
        }
    }

    private func resetTranslation() {
        translationTask?.cancel()
        translationTask = nil
        translation = .none
        copiedAll = false
    }
}

private struct TargetsRequest: Hashable {
    let request: UUID
    let state: ManualOCRSession.State
}

extension ClipDetailView {
    /// A held line reveals on its first tap; any other line copies.
    func tapRecognizedLine(_ index: Int) {
        let session = model.manualOCR
        guard session.lines.indices.contains(index) else { return }
        if session.heldLines.contains(index), !ocrRevealed.contains(index) {
            ocrRevealed.insert(index)
            return
        }
        let text = session.lines[index].text
        Task {
            guard await model.copyRecognizedText(text) else { return }
            ocrCopiedLine = index
            try? await Task.sleep(for: .seconds(1.2))
            if ocrCopiedLine == index { ocrCopiedLine = nil }
        }
    }
}
