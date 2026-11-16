import GanchoAppCore
import GanchoDesign
import SwiftUI

// MARK: - Action dock and chips

extension ClipPeek {
    /// The action dock, one row: Return's verb is the only filled control, the
    /// others are quiet text with their keys, and Actions closes the row. The
    /// widest tier that fits wins; Actions lists every verb either way.
    var dock: some View {
        let actions = dockActions
        let tiers = PeekDockFold.tiers(
            for: actions.map(\.id), primaryHasShortTitle: actions.first?.shortTitle != nil)
        // A slot of the row's own height: in the overlay the tiers are measured
        // once, at the final width, not for every width the peek's stacks probe.
        return Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: PeekActionButton.dockHeight * typeScale)
            .overlay {
                ViewThatFits(in: .horizontal) {
                    ForEach(tiers, id: \.self) { tier in
                        dockRow(actions, tier: tier)
                    }
                }
            }
            .onPreferenceChange(DockVisibleIDs.self) { [shown = $visibleDockIDs] ids in
                shown.wrappedValue = ids
            }
            .sheet(item: $recipeRequest) { request in
                TextRecipeReview(clipID: request.clipID).environment(model)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("peek-dock")
    }

    private func dockRow(_ actions: [PeekAction], tier: PeekDockFold.Tier) -> some View {
        let visible = tier.visible
        let shown = actions.filter { visible.contains($0.id) }
        // A Spacer would add a second gap to the width the tier is measured at.
        return HStack(spacing: GanchoTokens.Spacing.xxs) {
            HStack(spacing: GanchoTokens.Spacing.xxs) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, action in
                    actionButton(
                        action, index: index,
                        style: .dock(isPrimary: index == 0, short: tier.shortPrimary))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            actionsButton
        }
        .preference(key: DockVisibleIDs.self, value: visible)
    }

    /// The dock verbs in the row right now: the keyboard moves among these.
    var shownDockActions: [PeekAction] {
        let actions = dockActions
        let shown = actions.filter { visibleDockIDs.contains($0.id) }
        return shown.isEmpty ? actions : shown
    }

    func actionButton(
        _ action: PeekAction, index: Int, style: PeekActionButton.Style
    ) -> some View {
        PeekActionButton(
            action: action, style: style,
            isFocused: focus.wrappedValue == .peek && index == actionIndex
        ) {
            actionIndex = index
            action.run()
        }
    }
}

/// The ids of the dock tier on screen, reported by the row that fits.
private struct DockVisibleIDs: PreferenceKey {
    static let defaultValue: [String] = []

    static func reduce(value: inout [String], nextValue: () -> [String]) {
        value += nextValue()
    }
}
