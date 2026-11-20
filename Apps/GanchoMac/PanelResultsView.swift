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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ganchoOpaqueSurfaces) private var opaqueSurfaces
    @State private var listIsScrolling = false

    let query: String
    let hasActiveFilter: Bool
    let firstRunHint: LocalizedStringKey?
    let isGroupedView: Bool
    let groups: [PanelDateGroup]
    let items: [ClipItem]
    var searchFailure: ClipSearchError?
    var isSearching = false
    var retrySearch: () -> Void = {}
    var searchMode: PanelSearchMode = .fuzzy
    /// The other modes and scopes, counted, when nothing matches.
    var alternatives: [PanelAlternativeResult] = []
    /// The selected board's name, for the no-results line.
    var scopeName: String?
    var applyAlternative: (PanelSearchAlternative) -> Void = { _ in }
    /// Private Mode lists everything under one "Before private mode" header.
    var isPrivateMode = false
    /// The session around one result (Jump to context).
    var isContext = false
    let selectedID: UUID?
    var upwardMoveTarget: UUID?
    /// List rows, or a grid of cards `columns` wide; the grid reports the
    /// column count it fits so keyboard moves match what is on screen.
    let layout: PanelLayout
    let columns: Int
    let onColumnsChange: (Int) -> Void
    let clearFilters: () -> Void
    /// Opens the history importer from the first-run empty state.
    var importHistory: () -> Void = {}
    /// A user-driven scroll, as opposed to the list following the selection.
    var onUserScroll: () -> Void = {}
    /// Builds one row. `PanelView` owns row effects (selection, drag, context
    /// menu, pagination), so the row arrives already wired instead of this
    /// slice reaching for the state those effects need.
    let row: (ClipItem) -> RowContent

    var body: some View {
        if isSearching && items.isEmpty {
            ProgressView("Searching…")
                .accessibilityIdentifier("search-progress-indicator")
        } else if let searchFailure {
            SearchFailureNotice(failure: searchFailure, retry: retrySearch)
        } else if items.isEmpty {
            PanelResultsEmptyState(
                query: query,
                hasActiveFilter: hasActiveFilter,
                firstRunHint: firstRunHint,
                searchMode: searchMode,
                scopeName: scopeName,
                alternatives: alternatives,
                applyAlternative: applyAlternative,
                clearFilters: clearFilters,
                importHistory: importHistory)
        } else {
            if !showsSections || layout == .gallery { recentHeader }
            ScrollViewReader { proxy in
                ScrollView {
                    switch layout {
                    case .list:
                        LazyVStack(
                            spacing: GanchoTokens.Spacing.xxs,
                            pinnedViews: showsSections ? [.sectionHeaders] : []
                        ) {
                            if showsSections {
                                groupedRows
                            } else {
                                flatRows
                            }
                        }
                        .padding(.horizontal, GanchoTokens.Spacing.xxs)
                    case .gallery:
                        // Flat, in the same order as the grouped list: section
                        // headers would start new grid rows and break the
                        // index-by-columns arrow math.
                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.flexible(), spacing: GanchoTokens.Spacing.xs),
                                count: columns),
                            alignment: .leading, spacing: GanchoTokens.Spacing.xs
                        ) {
                            flatRows
                        }
                        .padding(.horizontal, GanchoTokens.Spacing.xs)
                        .onGeometryChange(for: CGFloat.self) {
                            $0.size.width
                        } action: { width in
                            onColumnsChange(PanelLayout.galleryColumns(forWidth: width))
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("panel-gallery")
                    }
                }
                .onChange(of: selectedID) { _, id in
                    guard let id else { return }
                    reveal(id, with: proxy)
                }
                .onScrollPhaseChange { _, phase in
                    listIsScrolling = phase != .idle
                    if phase == .interacting { onUserScroll() }
                }
                .environment(\.listIsScrolling, listIsScrolling)
            }
        }
    }

    private var showsSections: Bool { isGroupedView && !isPrivateMode }

    /// A row scrolled to the top edge lands behind the sticky header, so moving
    /// up reveals the row above it, or the top of the list for the first row.
    private func reveal(_ id: UUID, with proxy: ScrollViewProxy) {
        guard showsSections, layout == .list, id == upwardMoveTarget,
            let index = items.firstIndex(where: { $0.id == id })
        else {
            proxy.scrollTo(id)
            return
        }
        if index == 0 {
            proxy.scrollTo(id, anchor: .bottom)
        } else {
            proxy.scrollTo(items[index - 1].id)
        }
    }

    private var recentHeader: some View {
        HStack {
            if isContext {
                Text("Context")
            } else if !query.isEmpty {
                // The status the field's mode control sets: "Results · Exact".
                HStack(spacing: 0) {
                    Text("Results")
                    Text(verbatim: " · ")
                    Text(searchMode.title)
                }
            } else if isPrivateMode {
                Text("Before private mode")
            } else if hasActiveFilter {
                Text("Filtered")
            } else {
                Text("Recent")
            }
            Spacer()
            clipCount(items.count)
        }
        .peekCaps()
        .padding(.horizontal, GanchoTokens.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("results-header")
    }

    private var groupedRows: some View {
        ForEach(groups) { group in
            Section {
                ForEach(group.rows) { item in
                    row(item)
                }
            } header: {
                sectionHeader(group.section, count: group.rows.count)
            }
        }
    }

    private var flatRows: some View {
        ForEach(items) { item in row(item) }
    }

    /// A sticky section header — "Pinned" (with a pin glyph) or a semantic date
    /// (Today, Yesterday, This month, …) — with the section's clip count.
    private func sectionHeader(_ section: ClipSection, count: Int) -> some View {
        HStack(spacing: 4) {
            if section == .pinned {
                Image(systemName: "pin.fill").panelFont(size: 8)
            }
            Text(sectionTitle(section))
            Spacer()
            clipCount(count)
        }
        .peekCaps()
        .padding(.horizontal, GanchoTokens.Spacing.xs)
        .padding(.vertical, GanchoTokens.Spacing.xxs)
        // Pinned over scrolling rows, so it wears the panel's own surface: no band.
        .background {
            if opaqueSurfaces {
                Rectangle().fill(GanchoTokens.Palette.surface(.panel))
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("panel-section-header")
    }

    /// The bare number, spoken as "N clips". Rolling digits when a section
    /// grows or shrinks (a capture, a delete).
    private func clipCount(_ count: Int) -> some View {
        Text(verbatim: "\(count)")
            .contentTransition(.numericText(value: Double(count)))
            .animation(GanchoMotion.quick(reduceMotion: reduceMotion), value: count)
            .accessibilityLabel(Text("\(count) clips"))
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
    let firstRunHint: LocalizedStringKey?
    let searchMode: PanelSearchMode
    let scopeName: String?
    let alternatives: [PanelAlternativeResult]
    let applyAlternative: (PanelSearchAlternative) -> Void
    let clearFilters: () -> Void
    let importHistory: () -> Void

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
        // `.combine` would swallow the Import and Clear filters buttons.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            isNarrowed ? "panel-empty-noresults" : "panel-empty-firstrun")
    }

    private var firstRunContent: some View {
        Group {
            PanelEmptyMark()
                .padding(.bottom, GanchoTokens.Spacing.sm)
            Text("Nothing on the hook yet.")
                .panelFont(size: 22, design: .serif)
                .foregroundStyle(GanchoTokens.Palette.ink)
                .accessibilityIdentifier("panel-empty-title")
            Text("Copy anything, anywhere — it lands here, on this Mac, and stays yours.")
                .panelFont(.callout)
                .foregroundStyle(GanchoTokens.Palette.ink2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            if let firstRunHint {
                Text(firstRunHint)
                    .panelFont(.caption)
                    .foregroundStyle(GanchoTokens.Palette.ink3)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("panel-empty-capture-hint")
            }
            Button("Import from another app…", action: importHistory)
                .ganchoButtonStyle(.secondary)
                .padding(.top, GanchoTokens.Spacing.xs)
                .accessibilityIdentifier("panel-empty-import-button")
        }
    }

    private var noResultsContent: some View {
        Group {
            Text("No matches")
                .panelFont(size: 22, design: .serif)
                .foregroundStyle(GanchoTokens.Palette.ink)
                .accessibilityIdentifier("no-results-title")
            // A filter alone can empty the list: quoting an empty query back
            // would read as a bug.
            Text(
                PanelNoMatches.caption(query: query, scopeName: scopeName).text(mode: searchMode)
            )
            .panelFont(.callout)
            .foregroundStyle(GanchoTokens.Palette.ink2)
            .multilineTextAlignment(.center)
            .accessibilityIdentifier("no-results-caption")
            if !alternatives.isEmpty {
                PanelAlternativeList(results: alternatives, apply: applyAlternative)
            }
            if hasActiveFilter {
                // esc hides the panel, so a real button clears the filter.
                Button("Clear filters", action: clearFilters)
                    .ganchoTextButton()
                    .padding(.top, GanchoTokens.Spacing.xxs)
                    .accessibilityIdentifier("clear-filters")
            } else if PanelNoMatches.suggestsAnotherWord(
                hasActiveFilter: hasActiveFilter, results: alternatives)
            {
                Text("Try another word.")
                    .panelFont(.caption)
                    .foregroundStyle(GanchoTokens.Palette.ink3)
                    .padding(.top, GanchoTokens.Spacing.xxs)
            }
        }
    }
}
