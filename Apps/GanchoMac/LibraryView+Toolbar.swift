import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// How the Library lays out its clips; remembered between launches.
enum LibraryLayout: String, CaseIterable, Identifiable {
    case grid, list
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .grid: "Grid"
        case .list: "List"
        }
    }

    static let defaultsKey = "library-layout"
}

extension LibraryView {
    /// Search (⌘F), the Grid / List toggle and New board, above both panes.
    var toolbar: some View {
        HStack(spacing: GanchoTokens.Spacing.sm) {
            Spacer(minLength: 0)
            searchField.frame(width: 360)
            Spacer(minLength: 0)
            Picker("View", selection: $layout) {
                ForEach(LibraryLayout.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("library-layout")
            Button {
                boardNameField = ""
                boardSheet = .new
            } label: {
                Label("New board", systemImage: "plus").panelFont(.callout, .bold)
            }
            .buttonStyle(.borderedProminent)
            .tint(GanchoTokens.Palette.accent)
            .foregroundStyle(ContrastingForeground(on: GanchoTokens.Palette.accent))
            .accessibilityIdentifier("library-new-board")
        }
        .padding(.horizontal, GanchoTokens.Spacing.md)
        .frame(height: 52)
        .background {
            // ⌘F reaches the field from anywhere in the window.
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    private var searchField: some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search clips", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .accessibilityLabel(Text("Search the Library"))
                .accessibilityIdentifier("library-search-field")
            if searchText.isEmpty {
                Text(verbatim: "⌘F")
                    .panelFont(.caption2, .bold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                    .accessibilityHidden(true)
            } else {
                IconActionButton(
                    "Clear search", systemImage: "xmark.circle.fill",
                    identifier: "library-search-clear"
                ) { searchText = "" }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(.background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline))
    }

    /// Scope title and total, the kind chips, the sort and the sync state.
    var scopeHeader: some View {
        HStack(spacing: 10) {
            scopeTitle.panelFont(.title3, .heavy).lineLimit(1)
            if let total = visibleTotal {
                Text("\(total) clips").foregroundStyle(.secondary)
                    .accessibilityIdentifier("library-scope-count")
            }
            Divider().frame(height: 16)
            kindChips
            Picker("Sort", selection: $oldestFirst) {
                Text("Newest").tag(false)
                Text("Oldest").tag(true)
            }
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("library-sort")
            Spacer(minLength: 0)
            SyncStatusView(status: model.syncStatus)
        }
        .padding(.horizontal, GanchoTokens.Spacing.md)
        .padding(.vertical, GanchoTokens.Spacing.sm)
    }

    /// The scope's total less the clips hidden while their delete awaits Undo.
    private var visibleTotal: Int? {
        clipList.total.map { total in
            total - clipList.items.count { model.pendingDeletionIDs.contains($0.id) }
        }
    }

    /// The panel's kind set: the active chip names itself, the rest are glyphs.
    private var kindChips: some View {
        HStack(spacing: 4) {
            ForEach(ClipKindFilter.allCases) { filter in
                let active = kindFilter == filter
                Button {
                    kindFilter = filter
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: active ? "checkmark" : filter.symbolName)
                            .foregroundStyle(
                                active
                                    ? AnyShapeStyle(
                                        ContrastingForeground(on: GanchoTokens.Palette.accent))
                                    : AnyShapeStyle(
                                        filter.tintKind.map {
                                            GanchoTokens.Palette.kindTint(for: $0)
                                        }
                                            ?? .secondary))
                        if active { Text(filter.title) }
                    }
                    .panelFont(.caption, active ? .bold : .semibold)
                    .foregroundStyle(
                        active
                            ? AnyShapeStyle(ContrastingForeground(on: GanchoTokens.Palette.accent))
                            : AnyShapeStyle(.secondary)
                    )
                    .padding(.horizontal, active ? 8 : 0)
                    .frame(minWidth: 22, minHeight: 22)
                    .fixedSize()
                    .background(
                        active
                            ? AnyShapeStyle(GanchoTokens.Palette.accent)
                            : AnyShapeStyle(.quaternary.opacity(0.6)),
                        in: Capsule()
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(Text(filter.title))
                .accessibilityLabel(Text(filter.title))
                .accessibilityAddTraits(active ? .isSelected : [])
                .accessibilityIdentifier("library-kind-\(filter.rawValue)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Kind"))
    }
}
