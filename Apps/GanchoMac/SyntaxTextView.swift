import AppKit
import GanchoDesign
import SwiftUI

/// A monospaced, line-numbered code editor backed by `NSTextView` that applies
/// `GanchoSyntax` highlighting on every edit. Fully local — the text never
/// leaves the view. Used by the Library snippet editor; the tint matches the
/// floating-panel preview because both share `GanchoSyntax`.
///
/// It pins an explicit TextKit 1 stack (storage → layout manager → container):
/// the line-number ruler relies on the layout manager, which recent macOS no
/// longer exposes under the default TextKit 2 path.
struct SyntaxTextView: NSViewRepresentable {
    @Binding var text: String
    var accessibilityID: String

    init(text: Binding<String>, accessibilityID: String = "snippet-editor") {
        self._text = text
        self.accessibilityID = accessibilityID
    }

    static let editorFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer()
        container.widthTracksTextView = true
        layout.addTextContainer(container)

        let textView = NSTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.font = Self.editorFont
        textView.backgroundColor = GanchoTokens.Syntax.editorSurface
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset = NSSize(width: 8, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.setAccessibilityIdentifier(accessibilityID)
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = GanchoTokens.Syntax.editorSurface
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        let ruler = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = ruler

        context.coordinator.textView = textView
        context.coordinator.ruler = ruler
        context.coordinator.applyHighlight()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Only push external (model-driven) changes back into the view — never
        // the value the user is typing, which would fight the cursor.
        if textView.string != text {
            textView.string = text
            context.coordinator.applyHighlight()
            context.coordinator.ruler?.needsDisplay = true
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SyntaxTextView
        weak var textView: NSTextView?
        weak var ruler: LineNumberRulerView?

        init(_ parent: SyntaxTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            applyHighlight()
            ruler?.needsDisplay = true
        }

        /// Re-tint the whole document. Cheap for snippet-sized text, and the
        /// selection survives because only attributes change, not the string.
        func applyHighlight() {
            guard let textView, let storage = textView.textStorage else { return }
            let string = textView.string
            let whole = NSRange(location: 0, length: (string as NSString).length)
            storage.beginEditing()
            storage.setAttributes(
                [.font: SyntaxTextView.editorFont, .foregroundColor: NSColor.textColor],
                range: whole)
            for token in GanchoSyntax.tokens(in: string) {
                let nsRange = NSRange(token.range, in: string)
                storage.addAttribute(
                    .foregroundColor, value: GanchoTokens.Syntax.nsColor(for: token.kind),
                    range: nsRange)
                switch token.kind {
                case .comment:
                    storage.addAttribute(.obliqueness, value: 0.15, range: nsRange)
                case .placeholder:
                    storage.addAttribute(
                        .backgroundColor,
                        value: GanchoTokens.Syntax.nsColor(for: .placeholder)
                            .withAlphaComponent(0.16),
                        range: nsRange)
                default:
                    break
                }
            }
            storage.endEditing()
        }
    }
}

/// A line-number gutter for `SyntaxTextView`. Numbers hard lines (soft-wrapped
/// continuations are not re-numbered) using the text view's TextKit 1 layout
/// manager. Background and text colors come from the design tokens.
@MainActor
final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 36
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layout = textView.layoutManager else { return }

        GanchoTokens.Syntax.editorGutter.setFill()
        bounds.fill()

        let content = textView.string as NSString
        let inset = textView.textContainerInset.height
        let yOffset = convert(NSPoint.zero, from: textView).y
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font, .foregroundColor: GanchoTokens.Syntax.editorGutterText
        ]

        func draw(_ number: Int, atFragment fragment: NSRect) {
            let y = yOffset + fragment.minY + inset
            guard y + fragment.height >= rect.minY, y <= rect.maxY else { return }
            let label = "\(number)" as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(
                at: NSPoint(
                    x: ruleThickness - size.width - 6,
                    y: y + (fragment.height - size.height) / 2),
                withAttributes: attributes)
        }

        var line = 1
        var charIndex = 0
        let length = content.length
        while charIndex < length {
            let lineRange = content.lineRange(for: NSRange(location: charIndex, length: 0))
            let glyph = layout.glyphIndexForCharacter(at: lineRange.location)
            var effective = NSRange()
            let fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &effective)
            draw(line, atFragment: fragment)
            line += 1
            charIndex = NSMaxRange(lineRange)
        }
        // The trailing empty line: an empty document, or text ending in `\n`.
        if length == 0 || content.hasSuffix("\n") {
            draw(line, atFragment: layout.extraLineFragmentRect)
        }
    }
}
