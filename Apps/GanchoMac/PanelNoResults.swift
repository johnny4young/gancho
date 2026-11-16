import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// Re-probes the other modes whenever the query, its filters or its emptiness change.
struct PanelAlternativesKey: Equatable {
    let query: String
    let mode: PanelSearchMode
    let boardID: UUID?
    let kind: ClipKindFilter
    let app: String?
    let device: String?
    let before: Date?
    let isEmpty: Bool
    let meaningIsLoading: Bool
    var searchFailure: ClipSearchError?
    var isSearching = false
}

extension PanelSearchAlternative {
    var title: LocalizedStringResource {
        switch self {
        case .mode(let mode): mode.title
        case .allBoards: "All boards"
        }
    }

    var footerHint: LocalizedStringKey {
        switch self {
        case .mode(.fuzzy): "use fuzzy"
        case .mode(.exact): "use exact"
        case .mode(.regex): "use regex"
        case .mode(.meaning): "use meaning"
        case .allBoards: "use all boards"
        }
    }

    var identifier: String {
        switch self {
        case .mode(let mode): "no-results-alt-\(mode.rawValue)"
        case .allBoards: "no-results-alt-all-boards"
        }
    }

    /// The stage's headline: "Regex finds 3".
    func headline(total: Int) -> LocalizedStringKey {
        switch self {
        case .mode(let mode): "\(String(localized: mode.title)) finds \(total)"
        case .allBoards: "All boards have \(total)"
        }
    }
}

extension PanelSearchMode {
    /// How the no-results line names the mode: "…in Work, exact match."
    var matchPhrase: String {
        switch self {
        case .exact: String(localized: "exact match")
        case .fuzzy: String(localized: "fuzzy match")
        case .regex: String(localized: "regex match")
        case .meaning: String(localized: "by meaning")
        }
    }
}

extension PanelNoMatches.Caption {
    func text(mode: PanelSearchMode) -> LocalizedStringKey {
        switch self {
        case .filter: "No clips match this filter."
        case .query(let query): "No clips for “\(query)”, \(mode.matchPhrase)."
        case .scoped(let query, let scope):
            "No clips for “\(query)” in \(scope), \(mode.matchPhrase)."
        }
    }
}

/// The other modes and scopes, counted, as rows; ↓ takes the washed one.
struct PanelAlternativeList: View {
    let results: [PanelAlternativeResult]
    let apply: (PanelSearchAlternative) -> Void

    var body: some View {
        let washed = PanelNoMatches.washed(in: results)
        VStack(spacing: 5) {
            ForEach(results, id: \.alternative) { result in
                let isWashed = result.alternative == washed
                let shape = RoundedRectangle(
                    cornerRadius: GanchoTokens.Radius.md, style: .continuous)
                Button {
                    apply(result.alternative)
                } label: {
                    HStack(spacing: GanchoTokens.Spacing.xs) {
                        Text(result.alternative.title)
                            .panelFont(.callout, isWashed ? .semibold : .regular)
                        Spacer(minLength: GanchoTokens.Spacing.xs)
                        Text(verbatim: "\(result.total)")
                            .panelFont(size: 11.5, .medium, design: .monospaced)
                            .foregroundStyle(
                                isWashed ? GanchoTokens.Palette.ink : GanchoTokens.Palette.ink3)
                        if isWashed { KeyCap("↓").accessibilityHidden(true) }
                    }
                    .foregroundStyle(
                        isWashed ? GanchoTokens.Palette.ink : GanchoTokens.Palette.ink2
                    )
                    .padding(.horizontal, GanchoTokens.Spacing.sm)
                    .frame(height: 32)
                    .background(
                        isWashed ? GanchoTokens.Palette.selectionWash : Color.clear, in: shape
                    )
                    .overlay(
                        shape.strokeBorder(
                            GanchoTokens.Palette.hairline, lineWidth: GanchoTokens.Stroke.hairline)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    Text(
                        verbatim: "\(String(localized: result.alternative.title)), \(result.total)")
                )
                .accessibilityAddTraits(isWashed ? .isSelected : [])
                .accessibilityIdentifier(result.alternative.identifier)
            }
        }
        .padding(.top, GanchoTokens.Spacing.sm)
    }
}

/// The peek column while nothing matches: what ↓ would show.
struct PanelAlternativeStage: View {
    let result: PanelAlternativeResult
    let previewsHidden: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            Text(
                verbatim: String(localized: result.alternative.title) + " · "
                    + String(localized: "\(result.total) results")
            )
            .peekCaps()
            .accessibilityIdentifier("no-results-stage-label")
            HStack(alignment: .firstTextBaseline, spacing: GanchoTokens.Spacing.xs) {
                Text(result.alternative.headline(total: result.total))
                    .panelFont(size: 27, design: .serif)
                    .foregroundStyle(GanchoTokens.Palette.ink)
                    .lineLimit(1)
                    .accessibilityIdentifier("no-results-stage-title")
                Text(result.total == 1 ? "press ↓ to use it" : "press ↓ to use them")
                    .panelFont(.caption)
                    .foregroundStyle(GanchoTokens.Palette.ink3)
                    .lineLimit(1)
            }
            .padding(.bottom, GanchoTokens.Spacing.xxs)
            // Return does nothing here, so no row is selected: every cap is ⌘n.
            ForEach(Array(result.preview.enumerated()), id: \.element.id) { index, item in
                ClipCard(item: item, previewsHidden: previewsHidden, shortcutNumber: index + 1)
                    // A preview of the alternative, not a row of the list.
                    .accessibilityIdentifier("no-results-stage-row")
            }
            Spacer(minLength: 0)
        }
        .padding(GanchoTokens.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("no-results-stage")
    }
}
