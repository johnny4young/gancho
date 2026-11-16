import GanchoDesign
import GanchoKit
import SwiftUI

/// The keyboard surface. Without Full Access it shows the privacy explainer;
/// with it, a control bar plus a compact one-row strip or an expanded,
/// searchable list of cards. Tapping a clip inserts its text (or copies its
/// image to the pasteboard) into the active field.
struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if model.hasFullAccess {
                keyboard
            } else {
                FullAccessPrompt()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        // The keyboard runs outside the app, so it doesn't inherit the app's tint.
        .tint(GanchoTokens.Palette.controlTint)
        .task { await model.load() }
    }

    private var keyboard: some View {
        VStack(spacing: 8) {
            controlBar
            if let note = model.note {
                Label {
                    Text(note)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .font(.caption2)
                .foregroundStyle(GanchoTokens.Palette.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }
            if model.expanded {
                HStack(spacing: 8) {
                    if model.boards.isEmpty { Spacer(minLength: 0) } else { boardRow }
                    savePill
                }
                expandedList
            } else {
                compactRow
            }
        }
        .padding(10)
        .animation(GanchoMotion.smooth(reduceMotion: reduceMotion), value: model.note != nil)
        .animation(GanchoMotion.smooth(reduceMotion: reduceMotion), value: model.expanded)
        .animation(GanchoMotion.quick(reduceMotion: reduceMotion), value: model.entries)
    }

    // MARK: - Board filter (expanded mode)

    /// A tap-friendly board strip — All · Favorites · synced boards — shown only
    /// in the roomier expanded layout, beside Save clipboard.
    private var boardRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                boardChip(label: Text("All"), isActive: model.selectedBoardID == nil) {
                    model.selectBoard(nil)
                }
                ForEach(model.boards) { board in
                    boardChip(
                        label: board.displayTitle,
                        systemImage: board.sfSymbol,
                        dotColor: board.isSystem ? nil : BoardColors.color(for: board),
                        isActive: model.selectedBoardID == board.id
                    ) {
                        model.selectBoard(board.id)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func boardChip(
        label: Text, systemImage: String? = nil, dotColor: Color? = nil, isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let dotColor, !isActive {
                    Circle().fill(dotColor).frame(width: 7, height: 7)
                } else if let systemImage {
                    Image(systemName: systemImage).font(.caption2)
                }
                label.font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .ganchoChip(selected: isActive)
            .contentShape(.capsule)
        }
        .buttonStyle(PressableScale())
    }

    // MARK: - Control bar

    private var controlBar: some View {
        HStack(spacing: 10) {
            iconButton("globe", label: "Next keyboard", action: model.onNextKeyboard)

            if model.expanded {
                TextField("Search clips", text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: model.searchText) { _, _ in
                        model.searchTextChanged()
                    }
            } else {
                Spacer(minLength: 0)
            }

            // The expanded layout names Save beside the boards instead.
            HStack(spacing: 8) {
                if !model.expanded { saveButton }
                iconButton(
                    model.expanded ? "chevron.down" : "chevron.up",
                    label: "Toggle size", action: model.toggleExpand)
                iconButton("delete.left", label: "Delete", action: model.onDelete)
            }
        }
    }

    private var saveButton: some View {
        Button(action: model.saveClipboard) {
            Group {
                if model.saving {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            .font(.body.weight(.medium))
            .frame(width: 42, height: 36)
            .background(.tint.opacity(0.18), in: .rect(cornerRadius: 10))
            .contentShape(.rect)
        }
        .buttonStyle(PressableScale())
        .foregroundStyle(GanchoTokens.Palette.ink2)
        .accessibilityLabel("Save clipboard")
    }

    private var savePill: some View {
        Button(action: model.saveClipboard) {
            HStack(spacing: 5) {
                if model.saving {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "square.and.arrow.down").font(.caption2)
                }
                Text("Save clipboard").font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(GanchoTokens.Palette.ink)
            .overlay(
                Capsule().strokeBorder(
                    GanchoTokens.Palette.ink3, lineWidth: GanchoTokens.Stroke.hairline)
            )
            .contentShape(.capsule)
        }
        .buttonStyle(PressableScale())
        .fixedSize()
    }

    private func iconButton(
        _ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body)
                .frame(width: 42, height: 36)
                .contentShape(.rect)
        }
        .buttonStyle(PressableScale())
        .foregroundStyle(.primary)
        .accessibilityLabel(label)
    }

    // MARK: - Clip lists

    private var compactRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if model.entries.isEmpty {
                    emptyLabel
                } else {
                    ForEach(model.entries) { entry in
                        let isInserted = model.inserted.contains(entry.id)
                        Button {
                            model.insert(entry)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: ClipTile.symbolName(for: entry.kind))
                                    .font(.caption2)
                                    .foregroundStyle(GanchoTokens.Palette.ink2)
                                Text(entry.displayText)
                                    .lineLimit(1)
                                    .font(.callout)
                                if isInserted { insertedCaption }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(rowFill(isInserted), in: .capsule)
                            .contentShape(.capsule)
                        }
                        .buttonStyle(PressableScale())
                        .accessibilityValue(isInserted ? Text("Inserted") : Text(verbatim: ""))
                    }
                    // Trailing affordance so the one-row strip advertises the
                    // fuller, searchable list (the chevron in the control bar
                    // alone wasn't discoverable).
                    Button(action: model.toggleExpand) {
                        HStack(spacing: 4) {
                            Text("Show all clips")
                            Image(systemName: "chevron.right").imageScale(.small)
                        }
                        .font(.callout.weight(.medium))
                        .foregroundStyle(GanchoTokens.Palette.ink2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .contentShape(.capsule)
                    }
                    .buttonStyle(PressableScale())
                }
            }
            .padding(.horizontal, 2)
        }
    }

    /// The plain recent view groups into Pinned + date sections (mirroring the
    /// app); a board filter or a search renders the flat result list. A List, so
    /// every row carries native swipe actions (Copy, Delete) and the date
    /// sections get native headers.
    private var expandedList: some View {
        List {
            if model.entries.isEmpty {
                emptyLabel
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else if model.isGrouped {
                if let upNext = model.upNext { upNextRow(upNext) }
                ForEach(model.sections) { group in
                    Section {
                        ForEach(group.entries) { entry in swipeRow(entry) }
                    } header: {
                        Text(sectionTitle(group.section))
                    }
                }
            } else {
                ForEach(model.entries) { entry in swipeRow(entry) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
    }

    /// The clip the next tap would most likely want, with the keyboard's one
    /// accent: the hook that inserts it.
    private func upNextRow(_ entry: WidgetClipEntry) -> some View {
        let isInserted = model.inserted.contains(entry.id)
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.lg, style: .continuous)
        return Button {
            model.insert(entry)
        } label: {
            HStack(spacing: 10) {
                keyboardTile(for: entry)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Up next")
                        .font(.caption2.monospaced().weight(.medium))
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundStyle(GanchoTokens.Palette.ink3)
                    Text(entry.displayText)
                        .lineLimit(1)
                        .font(.callout)
                        .foregroundStyle(GanchoTokens.Palette.ink)
                }
                Spacer(minLength: 0)
                if isInserted { insertedCaption }
                HookMark()
                    .frame(width: 16, height: 16)
                    .frame(width: 32, height: 32)
                    .ganchoPrimaryVerb(in: Circle())
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 52)
            .background(rowFill(isInserted), in: shape)
            .overlay(
                shape.strokeBorder(
                    GanchoTokens.Palette.ink, lineWidth: GanchoTokens.Stroke.hairline)
            )
            .contentShape(shape)
        }
        .buttonStyle(PressableScale())
        .listRowInsets(EdgeInsets(top: 3, leading: 2, bottom: 3, trailing: 2))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .accessibilityValue(isInserted ? Text("Inserted") : Text(verbatim: ""))
        .accessibilityIdentifier("keyboard-up-next")
        .task(id: entry.id) { await model.ensureThumbnail(entry) }
    }

    /// One history row with its swipe actions: Copy (→ pasteboard, so it can be
    /// pasted in another app) leading, Delete trailing.
    private func swipeRow(_ entry: WidgetClipEntry) -> some View {
        clipRow(entry)
            .listRowInsets(EdgeInsets(top: 3, leading: 2, bottom: 3, trailing: 2))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .swipeActions(edge: .leading) {
                Button {
                    model.copy(entry)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .tint(.blue)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    model.delete(entry)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    private func clipRow(_ entry: WidgetClipEntry) -> some View {
        let isInserted = model.inserted.contains(entry.id)
        return Button {
            model.insert(entry)
        } label: {
            HStack(spacing: 10) {
                keyboardTile(for: entry)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayText)
                        .lineLimit(2)
                        .font(.callout)
                        .foregroundStyle(.primary)
                    metadataLine(for: entry)
                }
                Spacer(minLength: 0)
                if isInserted { insertedCaption }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(rowFill(isInserted), in: .rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(PressableScale())
        .accessibilityValue(isInserted ? Text("Inserted") : Text(verbatim: ""))
        .task(id: entry.id) { await model.ensureThumbnail(entry) }
    }

    /// Marks a row already typed into the current field.
    private var insertedCaption: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark").imageScale(.small)
            Text("Inserted").textCase(.lowercase)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(GanchoTokens.Palette.ink3)
        .accessibilityHidden(true)
    }

    /// Rows are cards on the keyboard; an inserted one takes the wash.
    private func rowFill(_ isInserted: Bool) -> Color {
        isInserted ? GanchoTokens.Palette.selectionWash : GanchoTokens.Palette.surface(.panel)
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

    private var emptyLabel: some View {
        Text("Nothing here yet")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }

    /// Leading tile, as the app's rows draw it: an image's thumbnail, a
    /// colour's swatch, otherwise the kind's glyph on the neutral fill.
    @ViewBuilder private func keyboardTile(for entry: WidgetClipEntry) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let outline = shape.strokeBorder(.separator, lineWidth: 0.5)
        if let thumbnail = model.thumbnail(for: entry.id) {
            thumbnail
                .resizable()
                .scaledToFill()
                .frame(width: 30, height: 30)
                .clipShape(shape)
                .overlay(outline)
        } else if entry.kind == .color, !entry.isSensitive,
            let value = ColorValue.parse(entry.displayText)
        {
            shape.fill(Color(Color.Resolved(value)))
                .frame(width: 30, height: 30)
                .overlay(outline)
        } else {
            shape
                .fill(GanchoTokens.Palette.controlFill)
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: ClipTile.symbolName(for: entry.kind))
                        .font(.system(size: 13))
                        .foregroundStyle(GanchoTokens.Palette.ink2)
                }
        }
    }

    /// "Safari · 2 min" — source app (cheap fallback name) and capture time,
    /// shown when the entry carries them.
    @ViewBuilder private func metadataLine(for entry: WidgetClipEntry) -> some View {
        let bundleID = entry.sourceAppBundleID
        if bundleID?.isEmpty == false || entry.createdAt != nil {
            HStack(spacing: 3) {
                if let bundleID, !bundleID.isEmpty {
                    Text(SourceApp.fallbackName(forBundleID: bundleID))
                    if entry.createdAt != nil { Text(verbatim: "·") }
                }
                if let createdAt = entry.createdAt {
                    Text(createdAt, style: .relative)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }
}

/// Press feedback for every tappable surface in the keyboard: a quick scale +
/// dim on touch-down so the intent ("this inserts / this acts") reads
/// instantly — the affordance a flat keyboard was missing.
struct PressableScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                configuration.isPressed
                    ? GanchoMotion.pressScale(reduceMotion: GanchoMotion.systemReducesMotion) : 1
            )
            .opacity(configuration.isPressed ? 0.65 : 1)
            .animation(GanchoMotion.press, value: configuration.isPressed)
    }
}

/// Shown until the user grants Full Access — the honest justification.
private struct FullAccessPrompt: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.largeTitle)
                .foregroundStyle(GanchoTokens.Palette.ink2)
            Text("Full Access needed")
                .font(.headline)
            Text(
                // swiftlint:disable:next line_length
                "Turn on Full Access in Settings → General → Keyboard → Keyboards → Gancho. Gancho never records what you type, and your clips leave this device only if you turn on iCloud sync."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
