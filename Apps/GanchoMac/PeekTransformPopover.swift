import GanchoAppCore
import GanchoDesign
import SwiftUI

/// The action panel behind the dock's Actions button and ⌘K: one filter over
/// the clip's verbs, its transforms, recipes and on-device Smart paste.
/// ↑↓ pick, ⏎ runs, esc closes.
struct PeekTransformPopover: View {
    let groups: [TransformGroup]
    let title: (TransformRow) -> String
    let groupTitle: (TransformGroup) -> Text
    let symbol: (TransformRow) -> String
    /// The key that runs the row outside this panel, when it has one.
    let key: (TransformRow) -> String?
    /// What the footer names beside "Runs on your Mac"; empty for verbs only.
    let footnote: String
    let onSelect: (TransformRow) -> Void

    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var filterFocused: Bool
    @Environment(\.panelTypeScale) private var typeScale

    private var filtered: [TransformGroup] {
        TransformCatalog.matching(groups, query: query, title: title)
    }

    private var rows: [TransformRow] { filtered.flatMap(\.rows) }

    /// Sized to the unfiltered list, so typing never resizes the panel.
    private var listHeight: CGFloat {
        let content = CGFloat(groups.flatMap(\.rows).count) * 28 + CGFloat(groups.count) * 24 + 8
        return min(content * typeScale, 330)
    }

    var body: some View {
        VStack(spacing: 0) {
            filter
            Divider()
            list.frame(height: listHeight)
            Divider()
            footer
        }
        .frame(width: 330)
        .onChange(of: query) { _, _ in highlighted = 0 }
        .onAppear { filterFocused = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Actions"))
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("transform-popover")
    }

    private var filter: some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(GanchoTokens.Palette.ink3)
                .accessibilityHidden(true)
            TextField("Filter actions", text: $query)
                .textFieldStyle(.plain)
                .ganchoCaret()
                .focused($filterFocused)
                .accessibilityIdentifier("transform-filter")
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-1) }
                .onKeyPress(.return) {
                    guard rows.indices.contains(highlighted) else { return .handled }
                    onSelect(rows[highlighted])
                    return .handled
                }
            KeyCap("esc").accessibilityHidden(true)
        }
        .panelFont(.callout)
        .padding(.horizontal, GanchoTokens.Spacing.sm)
        .padding(.vertical, GanchoTokens.Spacing.xs)
    }

    private var footer: some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            Label("Runs on your Mac", systemImage: "lock.shield")
            Spacer(minLength: 0)
            Text(verbatim: footnote).lineLimit(1)
        }
        .panelFont(size: 10.5)
        .foregroundStyle(GanchoTokens.Palette.ink3)
        .padding(.horizontal, GanchoTokens.Spacing.sm)
        .padding(.vertical, GanchoTokens.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("action-panel-footer")
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filtered) { group in
                        groupTitle(groups.first { $0.kind == group.kind } ?? group)
                            .peekCaps(size: 9.5)
                            .accessibilityAddTraits(.isHeader)
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
        let isDelete = row == .verb(.delete)
        let ink = isDelete ? GanchoTokens.Palette.danger : GanchoTokens.Palette.ink
        let rowKey = key(row)
        return Button {
            onSelect(row)
        } label: {
            HStack(spacing: GanchoTokens.Spacing.xs) {
                Image(systemName: symbol(row))
                    .frame(width: 16)
                    .foregroundStyle(isDelete ? ink : GanchoTokens.Palette.ink2)
                Text(verbatim: title(row))
                    .fontWeight(.medium)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                // Return runs the highlighted row: the panel's one accent.
                if let rowKey, !(isHighlighted && rowKey == "↩") {
                    KeyCap(rowKey).accessibilityHidden(true)
                }
                if isHighlighted { ReturnKeyCap() }
            }
            .panelFont(.callout)
            .padding(.horizontal, GanchoTokens.Spacing.xs)
            .padding(.vertical, 5)
            .background(
                isHighlighted
                    ? AnyShapeStyle(GanchoTokens.Palette.selectionWash) : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.card, style: .continuous)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: title(row)))
        .accessibilityValue(Text(verbatim: rowKey ?? ""))
        .accessibilityIdentifier(row.panelIdentifier)
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        guard !rows.isEmpty else { return .handled }
        highlighted = (highlighted + delta + rows.count) % rows.count
        return .handled
    }
}
