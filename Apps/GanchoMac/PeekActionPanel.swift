import GanchoAppCore
import GanchoDesign
import SwiftUI

/// The action panel behind the dock's Actions button and ⌘K: one filter over
/// the clip's verbs, its transforms, recipes and on-device Smart paste,
/// floating over the peek. ↑↓ pick, ⏎ runs, esc closes.
struct PeekActionPanel: View {
    let groups: [TransformGroup]
    let title: (TransformRow) -> String
    let groupTitle: (TransformGroup) -> Text
    let symbol: (TransformRow) -> String
    /// The key that runs the row outside this panel, when it has one.
    let key: (TransformRow) -> String?
    /// What the footer names beside "Runs on your Mac"; empty for verbs only.
    let footnote: String
    /// False for a row that has to wait, such as a new transform while one runs.
    let isEnabled: (TransformRow) -> Bool
    let onSelect: (TransformRow) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var filterFocused: Bool

    private var filtered: [TransformGroup] {
        TransformCatalog.matching(groups, query: query, title: title)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.lg, style: .continuous)
        let filtered = self.filtered
        let rows = filtered.flatMap(\.rows)
        VStack(spacing: 0) {
            filter(rows)
            Divider()
            list(filtered, rows: rows).frame(maxHeight: .infinity, alignment: .top)
            Divider()
            footer
        }
        .frame(maxWidth: 336, maxHeight: .infinity)
        // Opaque, not ganchoSurface: no glass inside the glass panel.
        .background(GanchoTokens.Palette.surface(.card), in: shape)
        .overlay {
            shape.strokeBorder(
                GanchoTokens.Palette.hairline, lineWidth: GanchoTokens.Stroke.hairline)
        }
        .clipShape(shape)
        .ganchoElevation(.overlay, cornerRadius: GanchoTokens.Radius.lg)
        .onChange(of: query) { _, _ in highlighted = 0 }
        // A field inserted this frame drops an immediate focus request.
        .task {
            await Task.yield()
            filterFocused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Actions"))
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("transform-popover")
    }

    private func filter(_ rows: [TransformRow]) -> some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(GanchoTokens.Palette.ink3)
                .accessibilityHidden(true)
            TextField("Filter actions", text: $query)
                .textFieldStyle(.plain)
                .ganchoCaret()
                .focused($filterFocused)
                .accessibilityIdentifier("transform-filter")
                .onKeyPress(.downArrow) { move(1, in: rows) }
                .onKeyPress(.upArrow) { move(-1, in: rows) }
                .onKeyPress(.return) {
                    guard rows.indices.contains(highlighted), isEnabled(rows[highlighted])
                    else { return .handled }
                    onSelect(rows[highlighted])
                    return .handled
                }
                .onKeyPress(.escape) {
                    // Closed next turn, so this esc never reaches the panel behind and hides it.
                    Task { @MainActor in
                        await Task.yield()
                        onClose()
                    }
                    return .handled
                }
            KeyCap("esc").accessibilityHidden(true)
        }
        .panelFont(.callout)
        .padding(.horizontal, GanchoTokens.Spacing.sm)
        .padding(.vertical, GanchoTokens.Spacing.sm)
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

    private func list(_ filtered: [TransformGroup], rows: [TransformRow]) -> some View {
        let current = rows.indices.contains(highlighted) ? rows[highlighted] : nil
        return ScrollViewReader { proxy in
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
                            rowButton(row, isHighlighted: row == current)
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
        let showsReturn = isHighlighted && isEnabled(row)
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
                if let rowKey, !(showsReturn && rowKey == "↩") {
                    KeyCap(rowKey).accessibilityHidden(true)
                }
                if showsReturn { ReturnKeyCap() }
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
        .disabled(!isEnabled(row))
        .accessibilityLabel(Text(verbatim: title(row)))
        .accessibilityValue(Text(verbatim: rowKey ?? ""))
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
        .accessibilityIdentifier(row.panelIdentifier)
    }

    private func move(_ delta: Int, in rows: [TransformRow]) -> KeyPress.Result {
        highlighted = TransformCatalog.movedHighlight(highlighted, by: delta, count: rows.count)
        return .handled
    }
}
