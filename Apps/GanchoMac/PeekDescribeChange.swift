import GanchoAppCore
import GanchoDesign
import SwiftUI

/// One change described in words and its result.
struct DescribedChange: Equatable {
    let prompt: String
    let input: String
    let output: String
}

/// "Describe the change": the request field, then the rewrite as a word diff,
/// what was there and what will paste, before anything is pasted.
struct PeekDescribeChange: View {
    let result: DescribedChange?
    let isThinking: Bool
    /// Prompts saved before this view opened.
    let savedPrompts: [String]
    let run: (String) -> Void
    let paste: (String) -> Void
    let copy: (String) -> Void
    let savePrompt: (String) -> Void
    let close: () -> Void
    @Binding var isEditing: Bool

    @State private var prompt = ""
    @State private var savedNow: Set<String> = []
    @FocusState private var promptFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.sm) {
            HStack(spacing: GanchoTokens.Spacing.xxs) {
                Image(systemName: "sparkles").foregroundStyle(GanchoTokens.Palette.accentInk)
                TextField("Describe the change", text: $prompt)
                    .textFieldStyle(.roundedBorder)
                    .focused($promptFocused)
                    .onSubmit(submit)
                    .onChange(of: prompt) { _, value in
                        if value.count > SavedPrompts.maximumLength {
                            prompt = String(value.prefix(SavedPrompts.maximumLength))
                        }
                    }
                    .disabled(isThinking)
                    .accessibilityIdentifier("describe-change-field")
                Button(action: close) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("Close")
                    .accessibilityLabel(Text("Close"))
                    .accessibilityIdentifier("describe-change-close")
            }
            if let result {
                let segments = WordDiff.diff(result.input, result.output)
                HStack(alignment: .top, spacing: GanchoTokens.Spacing.xs) {
                    box(Text("Was"), diff(segments, showing: .removed), isResult: false)
                        .accessibilityIdentifier("describe-change-was")
                    box(Text("Will paste"), diff(segments, showing: .added), isResult: true)
                        .accessibilityIdentifier("describe-change-will-paste")
                }
                ViewThatFits(in: .horizontal) {
                    actions(result, compact: false)
                    actions(result, compact: true)
                }
            }
        }
        .onAppear { promptFocused = true }
        .onChange(of: promptFocused, initial: true) { _, focused in isEditing = focused }
        .onDisappear { isEditing = false }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("describe-change")
    }

    private func submit() {
        let request = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, !isThinking else { return }
        run(request)
    }

    private func actions(_ result: DescribedChange, compact: Bool) -> some View {
        HStack(spacing: GanchoTokens.Spacing.xxs) {
            ActionButton(
                compact ? "Paste" : "Paste result", systemImage: "doc.on.clipboard",
                identifier: "describe-change-paste"
            ) { paste(result.output) }
            .help(Text(verbatim: "⇧⏎"))
            ActionButton(
                compact ? "Copy" : "Copy result", systemImage: "doc.on.doc",
                identifier: "describe-change-copy"
            ) { copy(result.output) }
            Spacer(minLength: 0)
            if !savedPrompts.contains(result.prompt), !savedNow.contains(result.prompt) {
                ActionButton(
                    compact ? "Save" : "Save prompt", systemImage: "bookmark",
                    identifier: "describe-change-save-prompt"
                ) {
                    savePrompt(result.prompt)
                    savedNow.insert(result.prompt)
                }
            }
        }
    }

    /// One side of the diff: unchanged words plain, this side's changes marked.
    private func diff(
        _ segments: [WordDiff.Segment], showing kind: WordDiff.Kind
    ) -> AttributedString {
        var text = AttributedString()
        for segment in segments where segment.kind == .same || segment.kind == kind {
            var part = AttributedString(segment.text)
            if segment.kind == .removed {
                part.strikethroughStyle = .single
                part.foregroundColor = GanchoTokens.Palette.danger
            } else if segment.kind == .added {
                part.foregroundColor = GanchoTokens.Palette.brandText
                part.backgroundColor = GanchoTokens.Palette.brandTint
            }
            text.append(part)
        }
        return text
    }

    private func box(_ label: Text, _ text: AttributedString, isResult: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
        return VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xxs) {
            label
                .textCase(.uppercase)
                .panelFont(.caption2, .bold)
                .foregroundStyle(
                    isResult
                        ? AnyShapeStyle(GanchoTokens.Palette.brandText) : AnyShapeStyle(.secondary))
            ScrollView {
                Text(text)
                    .panelFont(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(GanchoTokens.Spacing.xs)
        // Short enough that the actions stay in view above the dock.
        .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 92, alignment: .topLeading)
        .background(.background, in: shape)
        .overlay(shape.strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline))
    }
}
