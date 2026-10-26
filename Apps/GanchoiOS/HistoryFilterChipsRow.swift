import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// Active type and app filters as chips under the board rail: tap a chip to
/// remove it, or Clear filters to remove both. The board stays as it is.
struct HistoryFilterChipsRow: View {
    @Environment(IOSAppModel.self) private var model

    private var chips: [HistoryFilterChip] {
        HistoryFilterChip.chips(
            kind: model.kindFilter, appBundleID: model.selectedSourceAppBundleID)
    }

    var body: some View {
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: GanchoTokens.Spacing.xs) {
                    ForEach(chips, id: \.self) { chip in
                        Button {
                            remove(chip)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: symbol(chip)).font(.caption)
                                name(chip).font(.subheadline.weight(.medium)).lineLimit(1)
                                Image(systemName: "xmark").font(.caption2.weight(.bold))
                            }
                            .padding(.horizontal, GanchoTokens.Spacing.sm)
                            .padding(.vertical, GanchoTokens.Spacing.xs)
                            .foregroundStyle(Color(uiColor: .systemBackground))
                            .background(.primary, in: Capsule())
                            .frame(minHeight: GanchoTokens.HitTarget.touch)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Remove \(name(chip)) filter"))
                        .accessibilityIdentifier(identifier(chip))
                    }
                    Button {
                        model.kindFilter = nil
                        model.selectedSourceAppBundleID = nil
                    } label: {
                        Text("Clear filters")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, GanchoTokens.Spacing.sm)
                            .padding(.vertical, GanchoTokens.Spacing.xs)
                            .background(.quaternary, in: Capsule())
                            .frame(minHeight: GanchoTokens.HitTarget.touch)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("filter-clear")
                }
                .padding(.horizontal, GanchoTokens.Spacing.md)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("filter-chips")
        }
    }

    private func remove(_ chip: HistoryFilterChip) {
        switch chip {
        case .kind: model.kindFilter = nil
        case .app: model.selectedSourceAppBundleID = nil
        }
    }

    private func name(_ chip: HistoryFilterChip) -> Text {
        switch chip {
        case .kind(let kind): Text(LocalizedStringKey(kind.rawValue))
        case .app(let bundleID): Text(verbatim: SourceApp.fallbackName(forBundleID: bundleID))
        }
    }

    private func symbol(_ chip: HistoryFilterChip) -> String {
        switch chip {
        case .kind(let kind): kind.symbolName
        case .app: "app.dashed"
        }
    }

    private func identifier(_ chip: HistoryFilterChip) -> String {
        switch chip {
        case .kind: "filter-chip-kind"
        case .app: "filter-chip-app"
        }
    }
}
