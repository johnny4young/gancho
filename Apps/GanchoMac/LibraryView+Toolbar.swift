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
    /// Search (⌘F), the kind rail, the sort, Grid / List and New board, above both panes.
    var toolbar: some View {
        HStack(spacing: GanchoTokens.Spacing.sm) {
            searchField.frame(minWidth: 180, maxWidth: .infinity)
            kindRail
            Picker("Sort", selection: $oldestFirst) {
                Text("Newest").tag(false)
                Text("Oldest").tag(true)
            }
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("library-sort")
            Picker("View", selection: $layout) {
                ForEach(LibraryLayout.allCases) { Text($0.title).tag($0) }
            }
            .ganchoSegmented()
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("library-layout")
            Button {
                boardNameField = ""
                boardSheet = .new
            } label: {
                Label("New board", systemImage: "plus").panelFont(.callout, .medium)
            }
            .ganchoButtonStyle(.secondary)
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
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.card, style: .continuous)
        return HStack(spacing: GanchoTokens.Spacing.xs) {
            Image(systemName: "magnifyingglass").foregroundStyle(GanchoTokens.Palette.ink3)
                .accessibilityHidden(true)
            TextField("Search the Library", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .accessibilityIdentifier("library-search-field")
            if searchText.isEmpty {
                KeyCap("⌘F").accessibilityHidden(true)
            } else {
                IconActionButton(
                    "Clear search", systemImage: "xmark.circle.fill",
                    identifier: "library-search-clear"
                ) { searchText = "" }
                .foregroundStyle(GanchoTokens.Palette.ink3)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(GanchoTokens.Palette.controlFill, in: shape)
        .overlay(
            shape.strokeBorder(
                GanchoTokens.Palette.hairline, lineWidth: GanchoTokens.Stroke.hairline))
    }

    /// The panel's kind set as glyphs: the active one is ink on the wash.
    private var kindRail: some View {
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.sm, style: .continuous)
        return HStack(spacing: 2) {
            ForEach(ClipKindFilter.allCases) { filter in
                let active = kindFilter == filter
                Button {
                    kindFilter = filter
                } label: {
                    Image(systemName: filter.symbolName)
                        .panelFont(.caption, active ? .semibold : .regular)
                        .frame(width: 28, height: 26)
                        .ganchoTab(selected: active, in: shape)
                        .contentShape(shape)
                }
                .buttonStyle(.plain)
                .help(Text(filter.title))
                .accessibilityLabel(Text(filter.title))
                .accessibilityAddTraits(active ? .isSelected : [])
                .accessibilityIdentifier("library-kind-\(filter.rawValue)")
            }
        }
        .padding(2)
        .overlay(
            RoundedRectangle(cornerRadius: GanchoTokens.Radius.card, style: .continuous)
                .strokeBorder(
                    GanchoTokens.Palette.hairline, lineWidth: GanchoTokens.Stroke.hairline)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Kind"))
    }
}
