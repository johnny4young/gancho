import GanchoAppCore
import GanchoDesign
import SwiftUI

/// The single Transform list behind ⌘T: a filter over the clip's actions, text
/// transforms, recipes and on-device Smart paste. ↑↓ pick, ⏎ runs, esc closes.
struct PeekTransformPopover: View {
    let groups: [TransformGroup]
    let title: (TransformRow) -> String
    let groupTitle: (TransformGroup.Kind) -> Text
    let symbol: (TransformRow) -> String
    let onSelect: (TransformRow) -> Void

    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var filterFocused: Bool

    private var filtered: [TransformGroup] {
        TransformCatalog.matching(groups, query: query, title: title)
    }

    private var rows: [TransformRow] { filtered.flatMap(\.rows) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: GanchoTokens.Spacing.xs) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter actions", text: $query)
                    .textFieldStyle(.plain)
                    .focused($filterFocused)
                    .accessibilityIdentifier("transform-filter")
                    .onKeyPress(.downArrow) { move(1) }
                    .onKeyPress(.upArrow) { move(-1) }
                    .onKeyPress(.return) {
                        guard rows.indices.contains(highlighted) else { return .handled }
                        onSelect(rows[highlighted])
                        return .handled
                    }
            }
            .padding(.horizontal, GanchoTokens.Spacing.sm)
            .padding(.vertical, GanchoTokens.Spacing.xs)
            Divider()
            list
            if groups.contains(where: { $0.kind == .smartPaste }) {
                Divider()
                Label("Runs on your Mac — nothing leaves the device.", systemImage: "lock.shield")
                    .panelFont(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, GanchoTokens.Spacing.sm)
                    .padding(.vertical, GanchoTokens.Spacing.xs)
            }
        }
        .frame(width: 330, height: 318)
        .onChange(of: query) { _, _ in highlighted = 0 }
        .onAppear { filterFocused = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transform-popover")
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filtered) { group in
                        groupTitle(group.kind)
                            .textCase(.uppercase)
                            .panelFont(.caption2, .bold)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, GanchoTokens.Spacing.xs)
                            .padding(.top, GanchoTokens.Spacing.xs)
                            .padding(.bottom, 2)
                        ForEach(group.rows) { row in
                            rowButton(row, isHighlighted: rows.firstIndex(of: row) == highlighted)
                                .id(row.id)
                        }
                    }
                    if rows.isEmpty {
                        Text("No matching actions")
                            .panelFont(.callout)
                            .foregroundStyle(.secondary)
                            .padding(GanchoTokens.Spacing.sm)
                    }
                }
                .padding(.horizontal, GanchoTokens.Spacing.xxs)
                .padding(.vertical, 2)
            }
            .onChange(of: highlighted) { _, index in
                guard rows.indices.contains(index) else { return }
                proxy.scrollTo(rows[index].id)
            }
        }
    }

    private func rowButton(_ row: TransformRow, isHighlighted: Bool) -> some View {
        Button {
            onSelect(row)
        } label: {
            HStack(spacing: GanchoTokens.Spacing.xs) {
                Image(systemName: symbol(row))
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text(verbatim: title(row))
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isHighlighted {
                    Text(verbatim: "⏎")
                        .panelFont(.caption2, design: .monospaced)
                        .foregroundStyle(.secondary)
                }
            }
            .panelFont(.callout)
            .padding(.horizontal, GanchoTokens.Spacing.xs)
            .padding(.vertical, 5)
            .background(
                isHighlighted
                    ? AnyShapeStyle(GanchoTokens.Palette.accentTint) : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.card, style: .continuous)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("transform-row-\(row.id)")
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        guard !rows.isEmpty else { return .handled }
        highlighted = (highlighted + delta + rows.count) % rows.count
        return .handled
    }
}
