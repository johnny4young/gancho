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

/// The other modes and scopes, counted, as buttons; the best one is highlighted.
struct PanelAlternativeList: View {
    let results: [PanelAlternativeResult]
    let apply: (PanelSearchAlternative) -> Void

    var body: some View {
        let best = PanelAlternativeResult.best(of: results)?.alternative
        VStack(spacing: 5) {
            ForEach(results, id: \.alternative) { result in
                let isBest = result.alternative == best
                Button {
                    apply(result.alternative)
                } label: {
                    HStack {
                        Text(result.alternative.title).panelFont(.callout, .semibold)
                        Spacer(minLength: GanchoTokens.Spacing.xs)
                        Text(verbatim: "\(result.total)")
                            .panelFont(.caption, .semibold)
                            .monospacedDigit()
                            .padding(.horizontal, 6)
                            .frame(minWidth: 20, minHeight: 18)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                    .padding(.horizontal, GanchoTokens.Spacing.sm)
                    .frame(height: 34)
                    .background(
                        isBest
                            ? AnyShapeStyle(GanchoTokens.Palette.success.opacity(0.12))
                            : AnyShapeStyle(.quaternary),
                        in: RoundedRectangle(
                            cornerRadius: GanchoTokens.Radius.md, style: .continuous)
                    )
                    .overlay {
                        if isBest {
                            RoundedRectangle(
                                cornerRadius: GanchoTokens.Radius.md, style: .continuous
                            )
                            .strokeBorder(GanchoTokens.Palette.success.opacity(0.3))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    Text(
                        verbatim: "\(String(localized: result.alternative.title)), \(result.total)")
                )
                .accessibilityAddTraits(isBest ? .isSelected : [])
                .accessibilityIdentifier(result.alternative.identifier)
            }
        }
        .padding(.top, GanchoTokens.Spacing.xxs)
    }
}

/// The peek column while nothing matches: what the best alternative would show.
struct PanelAlternativeStage: View {
    let result: PanelAlternativeResult
    let previewsHidden: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            Text(
                verbatim: String(localized: result.alternative.title) + " · "
                    + String(localized: "\(result.total) results, press ↓ to use them")
            )
            .panelFont(.caption, .bold)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("no-results-stage-label")
            ForEach(Array(result.preview.enumerated()), id: \.element.id) { index, item in
                ClipCard(
                    item: item, isSelected: index == 0, previewsHidden: previewsHidden,
                    shortcutNumber: index + 1
                )
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
