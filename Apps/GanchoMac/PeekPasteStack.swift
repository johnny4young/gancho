import GanchoAppCore
import GanchoDesign
import GanchoKit
import KeyboardShortcuts
import SwiftUI

/// The paste stack in the peek: the clips in the order they paste, what
/// already went in, and the run's verbs in the dock. Return pastes the next
/// one and esc ends the run; the panel's search field owns both keys.
struct PeekPasteStack: View {
    @Environment(AppModel.self) private var model
    @Environment(\.panelTypeScale) private var typeScale
    /// Rows of the dock variant on screen; the dock's slot is this tall.
    @State private var dockRows = 1
    /// Ends an active run, then leaves the stack view.
    let close: () -> Void

    var body: some View {
        let shown = PasteStackPresentation(stack: model.pasteStack)
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.sm) {
            header(shown)
            List {
                ForEach(shown.rows) { row in
                    PasteStackRow(row: row, shown: shown)
                        .moveDisabled(row.state != .waiting)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                }
                .onMove { source, destination in
                    model.moveInStack(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("paste-stack-queue")
            dock(shown)
        }
        .padding(GanchoTokens.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // A clicked row takes the keyboard from the search field; the two
        // keys keep working from there.
        .onKeyPress(.return, phases: .down) { press in
            guard press.modifiers.isDisjoint(with: [.command, .option, .shift, .control])
            else { return .ignored }
            model.pasteNextFromStack()
            return .handled
        }
        .onKeyPress(.escape) {
            close()
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("peek-paste-stack")
    }

    private func header(_ shown: PasteStackPresentation) -> some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xxs) {
            HStack(spacing: 6) {
                Text("\(shown.count) clips")
                if case .pasteInto(let app) = model.pasteTarget.label {
                    Text(verbatim: "·").accessibilityHidden(true)
                    Text("Into \(app)").lineLimit(1)
                }
                Text(verbatim: "·").accessibilityHidden(true)
                Text("Pasted in order").lineLimit(1)
            }
            .peekCaps()
            HStack(alignment: .firstTextBaseline) {
                Text("Paste stack")
                    .panelFont(size: 27, design: .serif)
                    .foregroundStyle(GanchoTokens.Palette.ink)
                Spacer(minLength: GanchoTokens.Spacing.xs)
                Text(verbatim: shown.position)
                    .panelFont(size: 24, .medium, design: .monospaced)
                    .foregroundStyle(GanchoTokens.Palette.ink)
                    .accessibilityLabel(
                        Text("\(min(shown.cursor + 1, shown.count)) of \(shown.count)")
                    )
                    .accessibilityIdentifier("paste-stack-position")
            }
        }
    }

    // MARK: Dock

    /// One row while it fits, then without the optional keys, then two rows.
    private func dock(_ shown: PasteStackPresentation) -> some View {
        let verbs = shown.dock(
            skipKey: KeyboardShortcuts.getShortcut(for: .pasteStackSkip)?.description,
            backKey: KeyboardShortcuts.getShortcut(for: .pasteStackBack)?.description)
        let end = verbs.filter { $0.verb == .end }
        let primary = verbs.filter { $0.verb == .pasteNext }
        let quiet = verbs.filter { $0.verb != .end && $0.verb != .pasteNext }
        let rowHeight = PeekActionButton.dockHeight * typeScale
        let gaps = CGFloat(dockRows - 1) * GanchoTokens.Spacing.xxs
        // A slot of the dock's own height: in the overlay the variants are measured
        // once, at the final width, not for every width the peek's stacks probe.
        return Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: CGFloat(dockRows) * rowHeight + gaps)
            .overlay(alignment: .top) {
                ViewThatFits(in: .horizontal) {
                    dockRow(primary + quiet, end: end, shown: shown, keys: true)
                    dockRow(primary + quiet, end: end, shown: shown, keys: false)
                    VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xxs) {
                        dockRow(quiet, end: [], shown: shown, keys: true)
                        dockRow(primary, end: end, shown: shown, keys: true)
                    }
                    .preference(key: DockRowCount.self, value: 2)
                }
            }
            .onPreferenceChange(DockRowCount.self) { [rows = $dockRows] count in
                rows.wrappedValue = count
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("paste-stack-dock")
    }

    private func dockRow(
        _ verbs: [PasteStackPresentation.DockVerb], end: [PasteStackPresentation.DockVerb],
        shown: PasteStackPresentation, keys: Bool
    ) -> some View {
        HStack(spacing: GanchoTokens.Spacing.xxs) {
            ForEach(verbs, id: \.verb) { verb in
                let isPrimary = verb.verb == .pasteNext
                PeekActionButton(
                    action: action(for: verb, shown: shown, keys: keys || isPrimary),
                    style: .dock(isPrimary: isPrimary), isFocused: false
                ) { run(verb.verb) }
                .disabled(!verb.isEnabled)
                .opacity(verb.isEnabled || isPrimary ? 1 : 0.4)
            }
            Spacer(minLength: 0)
            ForEach(end, id: \.verb) { verb in
                endButton(verb, shown: shown, showsKey: keys)
            }
        }
    }

    private func action(
        for verb: PasteStackPresentation.DockVerb, shown: PasteStackPresentation, keys: Bool
    ) -> PeekAction {
        PeekAction(
            id: Self.identifier(verb.verb), title: title(verb.verb, shown: shown), symbol: "",
            shortcut: keys ? verb.key : nil, run: {})
    }

    /// Bordered, like the dock's Actions: it leaves the run rather than moving it.
    private func endButton(
        _ verb: PasteStackPresentation.DockVerb, shown: PasteStackPresentation, showsKey: Bool
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return Button(action: close) {
            HStack(spacing: 6) {
                Text(title(verb.verb, shown: shown)).panelFont(size: 12.5, .medium).lineLimit(1)
                if showsKey, let key = verb.key { KeyCap(key).accessibilityHidden(true) }
            }
            .padding(.horizontal, 7)
            .frame(height: PeekActionButton.dockHeight * typeScale)
            .foregroundStyle(GanchoTokens.Palette.ink)
            .overlay(
                shape.strokeBorder(
                    GanchoTokens.Palette.hairline, lineWidth: GanchoTokens.Stroke.hairline)
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityValue(Text(verbatim: verb.key ?? ""))
        .accessibilityIdentifier(Self.identifier(verb.verb))
    }

    private func title(
        _ verb: PasteStackPresentation.Verb, shown: PasteStackPresentation
    ) -> LocalizedStringKey {
        switch verb {
        case .pasteNext: "Paste next"
        case .skip: "Skip"
        case .back: "Back"
        case .reset: "Reset"
        case .end: shown.isRunActive ? "End run" : "Close"
        }
    }

    private func run(_ verb: PasteStackPresentation.Verb) {
        switch verb {
        case .pasteNext: model.pasteNextFromStack()
        case .skip: model.skipInStack()
        case .back: model.backInStack()
        case .reset: model.resetStack()
        case .end: close()
        }
    }

    private static func identifier(_ verb: PasteStackPresentation.Verb) -> String {
        switch verb {
        case .pasteNext: "paste-stack-next"
        case .skip: "paste-stack-skip"
        case .back: "paste-stack-back"
        case .reset: "paste-stack-reset"
        case .end: "paste-stack-end"
        }
    }
}

/// One stack entry: its place in a badge, the clip as its row, and what the
/// run did or will do with it.
private struct PasteStackRow: View {
    let row: PasteStackPresentation.Row
    let shown: PasteStackPresentation
    @Environment(AppModel.self) private var model
    @Environment(\.panelTypeScale) private var typeScale
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
        HStack(spacing: GanchoTokens.Spacing.xs) {
            badge
            HStack(spacing: GanchoTokens.Spacing.xs) {
                ClipCard(
                    item: row.clip, previewsHidden: model.previewsHidden,
                    thumbnail: model.thumbnails.cached(for: row.clip),
                    sensitiveLifetime: model.retentionPolicy.sensitiveLifetime)
                accessory
            }
            .padding(.trailing, GanchoTokens.Spacing.xs)
            .background(GanchoTokens.Palette.controlFill, in: shape)
            .overlay {
                if row.state == .next {
                    shape.strokeBorder(GanchoTokens.Palette.ink, lineWidth: 1.5)
                }
            }
        }
        .opacity(row.state == .pasted ? 0.5 : 1)
        .onHover { isHovered = $0 }
        .contextMenu {
            if row.canMoveUp { Button("Move up") { move(up: true) } }
            if row.canMoveDown { Button("Move down") { move(up: false) } }
            Button("Remove from stack") { remove() }
            Divider()
            Button("Clear") { model.clearStack() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(stateText)
        .accessibilityIdentifier("paste-stack-row")
        .accessibilityActions {
            if row.canMoveUp { Button("Move up") { move(up: true) } }
            if row.canMoveDown { Button("Move down") { move(up: false) } }
            Button("Remove") { remove() }
        }
    }

    private var stateText: Text {
        switch row.state {
        case .pasted: Text("Pasted")
        case .next: Text("Next")
        case .waiting: Text(verbatim: "")
        }
    }

    /// The place in the run; a pasted entry shows a checkmark in its place.
    private var badge: some View {
        let side = 22 * typeScale
        return Group {
            switch row.state {
            case .pasted:
                Image(systemName: "checkmark")
                    .panelFont(size: 10, .semibold)
                    .foregroundStyle(GanchoTokens.Palette.ink2)
                    .frame(width: side, height: side)
                    .background(GanchoTokens.Palette.controlFill, in: Circle())
            case .next:
                number.frame(width: side, height: side).ganchoInverseBadge(in: Circle())
            case .waiting:
                number.foregroundStyle(GanchoTokens.Palette.ink2)
                    .frame(width: side, height: side)
                    .overlay(
                        Circle().strokeBorder(
                            GanchoTokens.Palette.hairline, lineWidth: GanchoTokens.Stroke.hairline))
            }
        }
        .accessibilityHidden(true)
    }

    private var number: some View {
        Text(verbatim: "\(row.number)").panelFont(size: 10.5, .semibold, design: .monospaced)
    }

    @ViewBuilder private var accessory: some View {
        switch row.state {
        case .pasted:
            Text("Pasted").peekCaps(size: 9).accessibilityHidden(true)
        case .next:
            Text("next")
                .panelFont(.caption2, .medium)
                .foregroundStyle(GanchoTokens.Palette.ink2)
                .accessibilityHidden(true)
            ReturnKeyCap()
        case .waiting:
            if isHovered {
                Button(action: remove) {
                    Image(systemName: "xmark").panelFont(size: 10, .medium)
                }
                .buttonStyle(.plain)
                .foregroundStyle(GanchoTokens.Palette.ink2)
                .help("Remove from stack")
                .accessibilityHidden(true)
            }
            Image(systemName: "line.3.horizontal")
                .panelFont(size: 11)
                .foregroundStyle(GanchoTokens.Palette.ink3)
                .help("Drag to reorder")
                .accessibilityHidden(true)
        }
    }

    private func remove() {
        model.removeFromStack(entryID: row.id)
    }

    private func move(up: Bool) {
        guard let move = shown.move(row.id, up: up) else { return }
        model.moveInStack(fromOffsets: move.source, toOffset: move.destination)
    }
}

/// How many rows the dock variant on screen has; one unless it reports two.
private struct DockRowCount: PreferenceKey {
    static let defaultValue = 1

    static func reduce(value: inout Int, nextValue: () -> Int) {
        value = max(value, nextValue())
    }
}
