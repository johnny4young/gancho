import AppKit
import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// Read-only, full-content preview loaded only after the user explicitly asks
/// for it. Sensitive payloads never cross the shared loader's privacy gate.
struct ClipLargePreview: View {
    @Environment(AppModel.self) private var model
    let item: ClipItem
    let onClose: @MainActor () -> Void

    @State private var payload: ClipPreviewPayload?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            previewBody
        }
        .frame(minWidth: 640, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .background { closeShortcut }
        .task(id: item.id) {
            let store = model.store
            payload = await ClipPreviewLoader().load(item) { id in
                try await store.content(for: id)
            }
        }
    }

    private var header: some View {
        HStack(spacing: GanchoTokens.Spacing.sm) {
            Image(systemName: item.kind.symbolName)
                .font(.title2)
                .foregroundStyle(GanchoTokens.Palette.accent)
                .frame(width: 36, height: 36)
                .background(
                    GanchoTokens.Palette.accent.opacity(0.12),
                    in: RoundedRectangle(
                        cornerRadius: GanchoTokens.Radius.md, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 2) {
                if item.title.isEmpty {
                    Text(LocalizedStringKey(item.kind.rawValue))
                        .font(.headline)
                } else {
                    Text(verbatim: item.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                HStack(spacing: GanchoTokens.Spacing.sm) {
                    if let bundleID = item.sourceAppBundleID {
                        Text(verbatim: SourceApp.displayName(forBundleID: bundleID))
                    }
                    Text(item.createdAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Close", systemImage: "xmark") { onClose() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("large-preview-close")
        }
        .padding(GanchoTokens.Spacing.md)
    }

    @ViewBuilder private var previewBody: some View {
        switch payload {
        case nil:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("large-preview-loading")
        case .masked(let preview):
            Text(verbatim: preview)
                .font(.system(.title2, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(GanchoTokens.Spacing.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .privacySensitive()
                .accessibilityIdentifier("large-preview-masked")
        case .text(let text):
            if item.kind == .color, let color = Color(hexString: text) {
                colorPreview(color, value: text)
            } else {
                ClipPreviewTextView(text: text, highlightsCode: item.kind == .code)
            }
        case .binary(let data, _):
            binaryPreview(data)
        case .fileReferences(let paths):
            filePreview(paths)
        case .unavailable:
            ContentUnavailableView(
                "Preview unavailable", systemImage: "eye.slash",
                description: Text("The clip content couldn’t be loaded.")
            )
            .accessibilityIdentifier("large-preview-unavailable")
        }
    }

    private func colorPreview(_ color: Color, value: String) -> some View {
        VStack(spacing: GanchoTokens.Spacing.lg) {
            RoundedRectangle(cornerRadius: GanchoTokens.Radius.lg, style: .continuous)
                .fill(color)
                .frame(width: 280, height: 280)
                .overlay(
                    RoundedRectangle(cornerRadius: GanchoTokens.Radius.lg, style: .continuous)
                        .strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline)
                )
            Text(verbatim: value)
                .font(.title2.monospaced())
                .textSelection(.enabled)
                .accessibilityIdentifier("large-preview-content")
        }
        .padding(GanchoTokens.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func binaryPreview(_ data: Data) -> some View {
        if item.kind == .image, let image = NSImage(data: data) {
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(GanchoTokens.Spacing.md)
            }
            .accessibilityIdentifier("large-preview-image")
        } else if let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil)
        {
            ClipPreviewTextView(attributedText: attributed)
        } else {
            ContentUnavailableView("Preview unavailable", systemImage: "doc.questionmark")
                .accessibilityIdentifier("large-preview-unavailable")
        }
    }

    private func filePreview(_ paths: [String]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
                ForEach(Array(paths.enumerated()), id: \.offset) { _, path in
                    HStack(spacing: GanchoTokens.Spacing.sm) {
                        Image(systemName: "doc")
                            .foregroundStyle(GanchoTokens.Palette.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: URL(fileURLWithPath: path).lastPathComponent)
                                .font(.body.weight(.medium))
                            Text(verbatim: path)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(GanchoTokens.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        .quaternary.opacity(0.35),
                        in: RoundedRectangle(
                            cornerRadius: GanchoTokens.Radius.md, style: .continuous)
                    )
                }
            }
            .padding(GanchoTokens.Spacing.md)
        }
        .accessibilityIdentifier("large-preview-files")
    }

    /// A command-level shortcut wins over the field editor in the parent
    /// panel. Repeating Command-Y therefore toggles the preview closed.
    private var closeShortcut: some View {
        Button("") { onClose() }
            .keyboardShortcut("y", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}

/// NSTextView keeps very large documents scrollable and selectable without
/// SwiftUI laying out the entire string as one Text value. It is intentionally
/// read-only; no preview interaction can mutate clipboard history.
private struct ClipPreviewTextView: NSViewRepresentable {
    let text: String
    let attributedText: NSAttributedString?
    let highlightsCode: Bool
    let accessibilityID: String

    init(
        text: String, highlightsCode: Bool,
        accessibilityID: String = "large-preview-content"
    ) {
        self.text = text
        self.attributedText = nil
        self.highlightsCode = highlightsCode
        self.accessibilityID = accessibilityID
    }

    init(
        attributedText: NSAttributedString,
        accessibilityID: String = "large-preview-content"
    ) {
        self.text = attributedText.string
        self.attributedText = attributedText
        self.highlightsCode = false
        self.accessibilityID = accessibilityID
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = attributedText != nil
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.setAccessibilityIdentifier(accessibilityID)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        update(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        guard textView.string != text else { return }
        update(textView)
    }

    private func update(_ textView: NSTextView) {
        if let attributedText {
            textView.textStorage?.setAttributedString(attributedText)
            return
        }
        let font =
            highlightsCode
            ? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            : NSFont.systemFont(ofSize: 16)
        let value = NSMutableAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: NSColor.textColor])
        if highlightsCode, text.count <= 20_000 {
            for token in GanchoSyntax.tokens(in: text) {
                value.addAttribute(
                    .foregroundColor, value: GanchoTokens.Syntax.nsColor(for: token.kind),
                    range: NSRange(token.range, in: text))
            }
        }
        textView.textStorage?.setAttributedString(value)
    }
}
