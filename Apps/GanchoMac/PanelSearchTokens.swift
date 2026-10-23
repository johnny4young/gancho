import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

extension PanelSearchMode {
    var title: LocalizedStringKey {
        switch self {
        case .exact: "Exact"
        case .fuzzy: "Fuzzy"
        case .regex: "Regex"
        case .meaning: "Meaning"
        }
    }
}

/// The field's mode control. Meaning shows only while its index is on.
struct SearchModeControl: View {
    @Bindable var search: PanelSearchModel
    let showsMeaning: Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(modes, id: \.self) { mode in
                let isSelected = search.searchMode == mode
                Button {
                    search.searchMode = mode
                } label: {
                    Text(mode.title)
                        .panelFont(size: 10.5, .bold)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .foregroundStyle(
                            isSelected
                                ? AnyShapeStyle(
                                    ContrastingForeground(on: GanchoTokens.Palette.accent))
                                : AnyShapeStyle(.secondary)
                        )
                        .background {
                            if isSelected { Capsule().fill(GanchoTokens.Palette.accent) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("search-mode-\(mode.rawValue)")
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.07), in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Search mode"))
        .accessibilityIdentifier("search-mode")
    }

    private var modes: [PanelSearchMode] {
        PanelSearchMode.allCases.filter { showsMeaning || $0 != .meaning }
    }
}

/// One chip per filter a token set. Boards stay in the board rail, which
/// already shows the scope.
struct SearchTokenChips: View {
    @Bindable var search: PanelSearchModel

    var body: some View {
        ForEach(chips, id: \.key) { chip in
            HStack(spacing: 3) {
                Text(verbatim: "\(chip.key.spelling) \(chip.value)").lineLimit(1)
                Button {
                    search.removeFilter(chip.key)
                } label: {
                    Image(systemName: "xmark").panelFont(size: 8, .bold)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Remove filter"))
                .accessibilityIdentifier("search-token-remove-\(chip.key.rawValue)")
            }
            .panelFont(.caption, .semibold)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .ganchoTintedPill(GanchoTokens.Palette.indigo, wash: 0.14)
            .fixedSize()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("search-token-chip-\(chip.key.rawValue)")
        }
    }

    private var chips: [(key: SearchTokenKey, value: String)] {
        var chips: [(key: SearchTokenKey, value: String)] = []
        if let app = search.selectedSourceAppBundleID {
            chips.append((.app, SourceApp.displayName(forBundleID: app)))
        }
        if search.kindFilter != .all { chips.append((.type, search.kindFilter.rawValue)) }
        if let device = search.deviceName { chips.append((.device, device)) }
        if let before = search.createdBefore {
            chips.append((.before, before.formatted(date: .abbreviated, time: .omitted)))
        }
        return chips
    }
}

/// The completions for the word being typed; Tab takes the first.
struct SearchTokenPopover: View {
    let completions: [SearchTokenCompletion]
    let hint: (SearchTokenKey) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add a filter · Tab")
                .panelFont(size: 10, .bold)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.horizontal, GanchoTokens.Spacing.xs)
                .padding(.vertical, 4)
            ForEach(Array(completions.prefix(6).enumerated()), id: \.offset) { index, completion in
                HStack(spacing: GanchoTokens.Spacing.xs) {
                    Text(verbatim: key(of: completion))
                        .panelFont(.caption, design: .monospaced)
                        .foregroundStyle(ReadableInk(base: GanchoTokens.Palette.indigo))
                    Text(verbatim: detail(of: completion))
                        .panelFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, GanchoTokens.Spacing.xs)
                .frame(height: 26)
                .background {
                    if index == 0 {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(GanchoTokens.Palette.accentTint)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("search-token-completion")
            }
        }
        .padding(6)
        .frame(width: 280, alignment: .leading)
        .background(
            GanchoTokens.Palette.surface(.card),
            in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
        )
        .ganchoElevation(.overlay, cornerRadius: GanchoTokens.Radius.md)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search-token-popover")
    }

    private func key(of completion: SearchTokenCompletion) -> String {
        switch completion {
        case .key(let key): key.spelling
        case .value(let key, _): key.spelling
        }
    }

    private func detail(of completion: SearchTokenCompletion) -> String {
        switch completion {
        case .key(let key): hint(key)
        case .value(_, let candidate): candidate.title
        }
    }
}
