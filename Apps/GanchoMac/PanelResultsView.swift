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
    private let row: (Int, ClipItem) -> RowContent

    init(
        query: String,
        hasActiveFilter: Bool,
        firstRunHint: LocalizedStringKey,
        isGroupedView: Bool,
        groups: [PanelDateGroup],
        items: [ClipItem],
        selectedID: UUID?,
        clearFilters: @escaping () -> Void,
        @ViewBuilder row: @escaping (Int, ClipItem) -> RowContent
    ) {
        self.query = query
        self.hasActiveFilter = hasActiveFilter
        self.firstRunHint = firstRunHint
        self.isGroupedView = isGroupedView
        self.groups = groups
        self.items = items
        self.selectedID = selectedID
        self.clearFilters = clearFilters
        self.row = row
    }

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

    private var showsClearFilters: Bool {
        !query.isEmpty && hasActiveFilter
    }

    var body: some View {
        VStack(spacing: GanchoTokens.Spacing.xs) {
            if query.isEmpty {
                firstRunContent
            } else {
                noResultsContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, GanchoTokens.Spacing.lg)
        .accessibilityElement(children: showsClearFilters ? .contain : .combine)
        .accessibilityIdentifier(
            query.isEmpty ? "panel-empty-firstrun" : "panel-empty-noresults")
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
            Text("No clips for “\(query)”.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if showsClearFilters {
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
}
