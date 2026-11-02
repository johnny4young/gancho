import GanchoDesign
import GanchoKit
import SwiftUI

/// A merged clip's text, one part per block with a dashed rule between them.
struct PeekMergedParts: View {
    let parts: [String]
    let kind: ClipContentKind

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                if index > 0 {
                    DashedRule()
                        .stroke(
                            .separator,
                            style: StrokeStyle(
                                lineWidth: GanchoTokens.Stroke.hairline, dash: [4, 4])
                        )
                        .frame(height: GanchoTokens.Stroke.hairline)
                        .accessibilityHidden(true)
                }
                Text(verbatim: part)
                    .panelFont(.body, design: kind == .code ? .monospaced : .default)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityValue(Text("Part \(index + 1) of \(parts.count)"))
                    .accessibilityIdentifier("peek-part")
            }
        }
        .textSelection(.enabled)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("peek-merged-parts")
    }
}

nonisolated private struct DashedRule: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

/// The separator chips and Split under a merged clip.
struct PeekPartsControls: View {
    let separator: ClipParts.Separator
    let partCount: Int
    let isBusy: Bool
    let choose: (ClipParts.Separator) -> Void
    let split: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                separatorChips
                Spacer(minLength: GanchoTokens.Spacing.md)
                splitButton
            }
            VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
                HStack(spacing: 6) { separatorChips }
                splitButton
            }
        }
        .disabled(isBusy)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("peek-parts-controls")
    }

    @ViewBuilder private var separatorChips: some View {
        Text("Separator")
            .panelFont(.caption)
            .foregroundStyle(.secondary)
        ForEach(ClipParts.Separator.allCases, id: \.self) { option in
            chip(option)
        }
    }

    private var splitButton: some View {
        Button(action: split) {
            Label("Split into \(partCount) clips", systemImage: "square.grid.2x2")
        }
        .ganchoTextButton()
        .fixedSize()
        .accessibilityIdentifier("peek-split-parts")
    }

    private func chip(_ option: ClipParts.Separator) -> some View {
        let isOn = option == separator
        return Button {
            if !isOn { choose(option) }
        } label: {
            Text(option.title)
                .panelFont(.subheadline, isOn ? .semibold : .regular)
                .foregroundStyle(
                    isOn ? AnyShapeStyle(GanchoTokens.Palette.brandText) : AnyShapeStyle(.primary)
                )
                .padding(.horizontal, GanchoTokens.Spacing.xs)
                .frame(minHeight: 22)
                .background(
                    isOn
                        ? AnyShapeStyle(GanchoTokens.Palette.brandTint)
                        : AnyShapeStyle(Color.primary.opacity(0.07)),
                    in: Capsule()
                )
                .contentShape(Capsule())
                .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("peek-separator-\(option.rawValue)")
    }
}

extension ClipParts.Separator {
    fileprivate var title: LocalizedStringKey {
        switch self {
        case .newline: "Newline"
        case .space: "Space"
        case .comma: "Comma"
        }
    }
}
