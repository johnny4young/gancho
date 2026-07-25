import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// Passive presentation for the panel's empty, flat, and grouped result states.
///
/// Search input, selection, pagination, and row effects stay with `PanelView`.
/// This slice receives immutable presentation values and a row builder so it
/// cannot become a second navigation owner or reach into `AppModel`.
struct PanelResultsView<RowContent: View>: View {
    let query: String
    let hasActiveFilter: Bool
    let firstRunHint: LocalizedStringKey
    let isGroupedView: Bool
    let groups: [PanelDateGroup]
    let items: [ClipItem]
    let selectedID: UUID?
    let clearFilters: () -> Void
    /// Builds one row. `PanelView` owns row effects (selection, drag, context
    /// menu, pagination), so the row arrives already wired instead of this
    /// slice reaching for the state those effects need.
    let row: (Int, ClipItem) -> RowContent

    var body: some View {
        if items.isEmpty {
            PanelResultsEmptyState(
                query: query,
                hasActiveFilter: hasActiveFilter,
                firstRunHint: firstRunHint,
                clearFilters: clearFilters)
        } else {
            if !isGroupedView { recentHeader }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(
                        spacing: GanchoTokens.Spacing.xxs,
                        pinnedViews: isGroupedView ? [.sectionHeaders] : []
                    ) {
                        if isGroupedView {
                            groupedRows
                        } else {
                            flatRows
                        }
                    }
                    .padding(.horizontal, GanchoTokens.Spacing.xxs)
                }
                .onChange(of: selectedID) { _, id in
                    guard let id else { return }
                    proxy.scrollTo(id)
                }
            }
        }
    }

    private var recentHeader: some View {
        HStack {
            Text("Recent")
            Spacer()
            Text("\(items.count) clips")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.tertiary)
        .textCase(.uppercase)
        .padding(.horizontal, GanchoTokens.Spacing.xs)
    }

    private var groupedRows: some View {
        ForEach(groups) { group in
            Section {
                ForEach(group.rows, id: \.item.id) { entry in
                    row(entry.index, entry.item)
                }
            } header: {
                sectionHeader(group.section, count: group.rows.count)
            }
        }
    }

    private var flatRows: some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            row(index, item)
        }
    }

    /// A sticky section header — "Pinned" (with a pin glyph) or a semantic date
    /// (Today, Yesterday, This month, …) — with the section's clip count.
    private func sectionHeader(_ section: ClipSection, count: Int) -> some View {
        HStack(spacing: 4) {
            if section == .pinned {
                Image(systemName: "pin.fill").font(.system(size: 8))
            }
            Text(sectionTitle(section))
            Spacer()
            Text("\(count) clips")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.tertiary)
        .textCase(.uppercase)
        .padding(.horizontal, GanchoTokens.Spacing.xs)
        .padding(.vertical, GanchoTokens.Spacing.xxs)
        .background(.ultraThinMaterial)
    }

    private func sectionTitle(_ section: ClipSection) -> LocalizedStringKey {
        switch section {
        case .pinned: "Pinned"
        case .date(let bucket): bucketTitle(bucket)
        }
    }

    private func bucketTitle(_ bucket: DateBucket) -> LocalizedStringKey {
        switch bucket {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .thisMonth: "This month"
        case .lastMonth: "Last month"
        case .thisYear: "This year"
        case .lastYear: "Last year"
        case .older: "Older"
        }
    }
}

private struct PanelResultsEmptyState: View {
    let query: String
    let hasActiveFilter: Bool
    let firstRunHint: LocalizedStringKey
    let clearFilters: () -> Void

    /// The list is empty because the user narrowed it — not because history is
    /// empty. A type, board, or source filter can be active with no query at
    /// all (say, the Images pill on a history that has no images), and that
    /// state must not masquerade as first run: the first-run copy would claim
    /// the history is empty and, carrying no Clear filters button, would leave
    /// the user without a way back.
    private var isNarrowed: Bool { !query.isEmpty || hasActiveFilter }

    var body: some View {
        VStack(spacing: GanchoTokens.Spacing.xs) {
            if isNarrowed {
                noResultsContent
            } else {
                firstRunContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, GanchoTokens.Spacing.lg)
        // `.combine` flattens children into one element, which would swallow
        // the Clear filters button; contain only when that button is present.
        .accessibilityElement(children: hasActiveFilter ? .contain : .combine)
        .accessibilityIdentifier(
            isNarrowed ? "panel-empty-noresults" : "panel-empty-firstrun")
    }

    private var firstRunContent: some View {
        Group {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(
                    GanchoTokens.Palette.success.gradient,
                    in: RoundedRectangle(
                        cornerRadius: GanchoTokens.Radius.xl, style: .continuous)
                )
                .padding(.bottom, GanchoTokens.Spacing.xs)
            Text("Your history starts here")
                .font(.headline)
            Text(
                "Copy anything — text, a link, an image — and it appears here, ready to paste again."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            Text(firstRunHint)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, GanchoTokens.Spacing.xxs)
        }
    }

    private var noResultsContent: some View {
        Group {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 64, height: 64)
                .background(
                    .quaternary,
                    in: RoundedRectangle(
                        cornerRadius: GanchoTokens.Radius.xl, style: .continuous)
                )
                .padding(.bottom, GanchoTokens.Spacing.xs)
            Text("No matches")
                .font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if hasActiveFilter {
                // esc hides the panel, so a "press esc" hint would be wrong; a
                // real button clears the type/board/source filter narrowing
                // the list.
                Button("Clear filters", action: clearFilters)
                    .buttonStyle(.borderless)
                    .padding(.top, GanchoTokens.Spacing.xxs)
                    .accessibilityIdentifier("clear-filters")
            } else {
                Text("Try another word.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, GanchoTokens.Spacing.xxs)
            }
        }
    }

    /// A filter alone can empty the list, and quoting an empty query back at
    /// the user ("No clips for “”.") would read as a bug.
    private var detail: LocalizedStringKey {
        query.isEmpty ? "No clips match this filter." : "No clips for “\(query)”."
    }
}
