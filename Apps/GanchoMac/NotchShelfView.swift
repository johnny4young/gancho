import AppKit
import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// The shelf that hangs from the notch: boards on the left, actions on the
/// right. Dark by design, in both appearances.
struct NotchShelfView: View {
    nonisolated static let space = "notch-shelf"
    static let maxBoards = 6

    let state: NotchShelfState

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            bottomLeadingRadius: GanchoTokens.Radius.xl,
            bottomTrailingRadius: GanchoTokens.Radius.xl, style: .continuous)
    }

    var body: some View {
        HStack(alignment: .top, spacing: GanchoTokens.Spacing.sm) {
            if !state.boards.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    heading("Drop on a board")
                    ForEach(state.boards) { board in
                        boardRow(board)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 6) {
                heading(state.boards.isEmpty ? "Drop on an action" : "Or an action")
                Grid(
                    horizontalSpacing: GanchoTokens.Spacing.xs,
                    verticalSpacing: GanchoTokens.Spacing.xs
                ) {
                    GridRow {
                        tile(
                            .extractText, "Extract text", symbol: "text.viewfinder",
                            id: "extract-text")
                        tile(.resize, "Resize", symbol: "photo", id: "resize")
                    }
                    GridRow {
                        tile(
                            .stripLocation, "Strip location", symbol: "location.slash",
                            id: "strip-location")
                        tile(.newBoard, "New board", symbol: "plus", id: "new-board")
                    }
                }
            }
            .frame(width: 196, alignment: .leading)
        }
        .padding(14)
        .frame(width: 440)
        .background(Color(nsColor: .windowBackgroundColor), in: shape)
        .overlay(shape.strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline))
        .coordinateSpace(.named(Self.space))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notch-shelf")
    }

    private func heading(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption2.weight(.heavy))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    private func boardRow(_ board: Pinboard) -> some View {
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.card, style: .continuous)
        let count = state.counts[board.id] ?? 0
        return HStack(spacing: GanchoTokens.Spacing.xs) {
            BoardIdentityMark(board: board, size: 10)
            board.displayTitle
                .font(.callout)
                .lineLimit(1)
            Spacer(minLength: 0)
            if count > 0 {
                Text(verbatim: "\(count)")
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(.fill.tertiary, in: shape)
        .modifier(
            BoardDropFeedback(
                isTargeted: state.hovered == .board(board.id), pulses: false, ring: shape)
        )
        .modifier(TargetFrame(target: .board(board.id), state: state))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(board.displayTitle)
        .accessibilityIdentifier("notch-shelf-board-\(board.id.uuidString)")
    }

    private func tile(
        _ target: NotchShelfTarget, _ title: LocalizedStringKey, symbol: String, id: String
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
        let isAvailable = !target.needsImage || state.mayBeImage
        return VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 92, height: 70)
        .background(.fill.secondary, in: shape)
        .opacity(isAvailable ? 1 : 0.4)
        .modifier(
            BoardDropFeedback(isTargeted: state.hovered == target, pulses: false, ring: shape)
        )
        .modifier(TargetFrame(target: target, state: state))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(isAvailable ? Text(verbatim: "") : Text("Images only"))
        .accessibilityIdentifier("notch-shelf-action-\(id)")
    }
}

/// Reports a target's frame so the drop view can tell what lies under the pointer.
private struct TargetFrame: ViewModifier {
    let target: NotchShelfTarget
    let state: NotchShelfState

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(NotchShelfView.space))
        } action: { frame in
            state.frames[target] = frame
        }
    }
}
