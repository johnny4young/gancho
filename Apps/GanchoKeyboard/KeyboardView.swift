import GanchoDesign
import GanchoKit
import SwiftUI

/// The keyboard surface. Without Full Access it shows the privacy explainer;
/// with it, a control bar plus a compact one-row strip or an expanded,
/// searchable list of cards. Tapping a clip inserts its text (or copies its
/// image to the pasteboard) into the active field.
struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel

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
        .task { await model.load() }
    }

    private var keyboard: some View {
        VStack(spacing: 8) {
            controlBar
            if let note = model.note {
                Label(note, systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
            if model.expanded {
                if !model.boards.isEmpty { boardRow }
                expandedList
            } else {
                compactRow
            }
        }
        .padding(10)
        .animation(.easeInOut(duration: 0.15), value: model.note != nil)
        .animation(.snappy(duration: 0.22), value: model.expanded)
        .animation(.snappy(duration: 0.22), value: model.entries)
    }

    // MARK: - Board filter (expanded mode)

    /// A tap-friendly board strip — All · Favorites · synced boards — shown only
    /// in the roomier expanded layout so the compact one-row strip stays minimal.
    private var boardRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                boardChip(label: Text("All"), isActive: model.selectedBoardID == nil) {
                    model.selectBoard(nil)
                }
                ForEach(model.boards) { board in
                    boardChip(
                        label: board.isSystem ? Text("Favorites") : Text(verbatim: board.name),
                        systemImage: board.sfSymbol,
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
        label: Text, systemImage: String? = nil, isActive: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage).font(.caption2) }
                label.font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary), in: .capsule
            )
            .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
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
                        Task { await model.runSearch() }
                    }
            } else {
                Spacer(minLength: 0)
            }

            // Action cluster: clearly spaced, with the primary save tinted.
            HStack(spacing: 8) {
                saveButton
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
        .foregroundStyle(.tint)
        .accessibilityLabel("Save clipboard")
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
                        Button {
                            model.insert(entry)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: entry.kind.symbolName)
                                    .font(.caption2)
                                    .foregroundStyle(GanchoTokens.Palette.kindTint(for: entry.kind))
                                Text(entry.displayText)
                                    .lineLimit(1)
                                    .font(.callout)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(.fill.tertiary, in: .capsule)
                            .contentShape(.capsule)
                        }
                        .buttonStyle(PressableScale())
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    /// The plain recent view groups into Pinned + date sections (mirroring the
    /// app); a board filter or a search renders the flat result list.
    private var expandedList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if model.entries.isEmpty {
                    emptyLabel.padding(.vertical, 12)
                } else if model.isGrouped {
                    ForEach(model.sections) { group in
                        sectionHeader(group.section)
                        ForEach(group.entries) { entry in clipRow(entry) }
                    }
                } else {
                    ForEach(model.entries) { entry in clipRow(entry) }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func clipRow(_ entry: WidgetClipEntry) -> some View {
        Button {
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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.fill.quaternary, in: .rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(PressableScale())
        .task(id: entry.id) { await model.ensureThumbnail(entry) }
    }

    private func sectionHeader(_ section: ClipSection) -> some View {
        Text(sectionTitle(section))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .padding(.bottom, 1)
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

    /// Leading tile: the image clip's thumbnail when one is loaded, otherwise the
    /// kind glyph on a tint-washed rounded square (matches the app's history row).
    @ViewBuilder private func keyboardTile(for entry: WidgetClipEntry) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        if let thumbnail = model.thumbnail(for: entry.id) {
            thumbnail
                .resizable()
                .scaledToFill()
                .frame(width: 30, height: 30)
                .clipShape(shape)
                .overlay(shape.strokeBorder(.separator, lineWidth: 0.5))
        } else {
            let tint = GanchoTokens.Palette.kindTint(for: entry.kind)
            shape
                .fill(tint.opacity(0.18))
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: entry.kind.symbolName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
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
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .opacity(configuration.isPressed ? 0.65 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Shown until the user grants Full Access — the honest justification.
private struct FullAccessPrompt: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.largeTitle)
                .foregroundStyle(.tint)
            Text("Full Access needed")
                .font(.headline)
            Text(
                "Turn on Full Access in Settings → General → Keyboard → Keyboards → Gancho. Nothing you copy or type ever leaves your device."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
