import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// The Transform pipeline: the steps in order (drag to reorder, × to remove,
/// + step to chain), the text before and what will paste after.
struct PeekTransformPipeline: View {
    @Binding var pipeline: TransformPipeline
    let source: String
    let availableSteps: [TransformStep]
    let title: (TransformStep) -> String
    let paste: (String) -> Void
    let copy: (String) -> Void
    let close: () -> Void

    var body: some View {
        let outcome = pipeline.run(on: source)
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.sm) {
            HStack(alignment: .top) {
                FlowLayout(spacing: GanchoTokens.Spacing.xxs) {
                    ForEach(Array(pipeline.steps.enumerated()), id: \.offset) { index, step in
                        if index > 0 {
                            Image(systemName: "arrow.right")
                                .panelFont(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(height: 24)
                        }
                        stepChip(step, at: index)
                    }
                    addStepMenu
                }
                // Keeps the first chip's capsule clear of the scroll view's edge.
                .padding(.leading, 1)
                Spacer(minLength: 0)
                Button(action: close) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close")
                .accessibilityLabel(Text("Close"))
                .accessibilityIdentifier("transform-close")
            }
            HStack(alignment: .top, spacing: GanchoTokens.Spacing.xs) {
                box(Text("Before"), text: source, isResult: false)
                    .accessibilityIdentifier("transform-before")
                switch outcome {
                case .text(let result):
                    box(Text("After · will paste"), text: result, isResult: true)
                        .accessibilityIdentifier("transform-after")
                case .failed(let index):
                    box(
                        Text("After · will paste"),
                        text: String(localized: "Step \(index + 1) can’t transform this text."),
                        isResult: true
                    )
                    .foregroundStyle(GanchoTokens.Palette.warningInk)
                    .accessibilityIdentifier("transform-after")
                }
            }
            if case .text(let result) = outcome {
                HStack(spacing: GanchoTokens.Spacing.xxs) {
                    ActionButton(
                        "Paste result", systemImage: "doc.on.clipboard",
                        identifier: "transform-paste-result"
                    ) { paste(result) }
                    .help(Text(verbatim: "⇧⏎"))
                    ActionButton(
                        "Copy result", systemImage: "doc.on.doc",
                        identifier: "transform-copy-result"
                    ) { copy(result) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transform-pipeline")
    }

    private func stepChip(_ step: TransformStep, at index: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
            Text(verbatim: title(step))
            Button {
                pipeline.remove(at: index)
                if pipeline.isEmpty { close() }
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Remove step"))
        }
        .panelFont(.caption, .medium)
        .padding(.horizontal, GanchoTokens.Spacing.xs)
        .frame(height: 24)
        .background(.background, in: .rect(cornerRadius: GanchoTokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: GanchoTokens.Radius.md)
                .strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline)
        )
        .draggable(String(index))
        .dropDestination(for: String.self) { items, _ in
            guard let source = items.first.flatMap(Int.init) else { return false }
            pipeline.move(from: source, to: index)
            return true
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("transform-step-chip")
    }

    private var addStepMenu: some View {
        Menu {
            ForEach(availableSteps, id: \.self) { step in
                Button(title(step)) { pipeline.append(step) }
            }
        } label: {
            Label("Step", systemImage: "plus")
                .panelFont(.caption, .medium)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .frame(height: 24)
        .disabled(pipeline.isFull)
        .accessibilityIdentifier("transform-add-step")
    }

    private func box(_ label: Text, text: String, isResult: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
        return VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xxs) {
            label
                .textCase(.uppercase)
                .panelFont(.caption2, .bold)
                .foregroundStyle(
                    isResult
                        ? AnyShapeStyle(GanchoTokens.Palette.brandText) : AnyShapeStyle(.secondary))
            ScrollView {
                Text(verbatim: ClipTextPreview.truncated(text, limit: 8_000))
                    .panelFont(.caption, design: .monospaced)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(GanchoTokens.Spacing.xs)
        .frame(maxWidth: .infinity, minHeight: 90, maxHeight: 160, alignment: .topLeading)
        .background(
            isResult ? AnyShapeStyle(GanchoTokens.Palette.brandTint) : AnyShapeStyle(.background),
            in: shape
        )
        .overlay(shape.strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline))
    }
}
