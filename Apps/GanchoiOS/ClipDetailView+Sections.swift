import GanchoAI
import GanchoDesign
import GanchoKit
import SwiftUI
import UIKit

extension ClipDetailView {
    /// Kind, source app, device and age, as one line of small caps.
    var provenanceCaption: some View {
        var parts = [Text(LocalizedStringKey(item.kind.rawValue))]
        if requiresMasking { parts.append(Text("Masked")) }
        if let bundleID = item.sourceAppBundleID, !bundleID.isEmpty {
            parts.append(Text(verbatim: SourceApp.fallbackName(forBundleID: bundleID)))
        }
        if let device = item.sourceDeviceName, !device.isEmpty {
            parts.append(Text(verbatim: device))
        }
        parts.append(Text(.currentDate, format: .reference(to: item.createdAt, maxFieldCount: 1)))
        return parts.dropFirst().reduce(parts[0]) { Text("\($0) · \($1)") }
            .font(dataFont(11, .caption2, weight: .medium))
            .textCase(.uppercase)
            .tracking(0.8)
            .accessibilityIdentifier("detail-provenance")
    }

    /// Where the clip came from, first.
    var provenanceRow: some View {
        Section {
            provenanceCaption
                .foregroundStyle(GanchoTokens.Palette.ink3)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(Color.clear)
        }
    }

    /// Site first: the host in full ink, its decoded path quieter behind it.
    private func linkHeadline(_ parts: ClipLinkParts) -> AttributedString {
        var host = AttributedString(parts.host)
        host.font = .title2.weight(.heavy)
        var path = AttributedString(LinkAnatomy(text: parts.text)?.path ?? "")
        path.font = .title2
        path.foregroundColor = GanchoTokens.Palette.ink3
        return host + path
    }

    /// A link as itself: its host large, the full URL, and what decoding and
    /// the scheme add. A tint and a full outline mark it, never a side bar.
    func linkHero(_ parts: ClipLinkParts) -> some View {
        let tint = GanchoTokens.Palette.kindTint(for: .url)
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.lg, style: .continuous)
        return Section {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(linkHeadline(parts))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    // An editable link keeps its edit, behind the hero.
                    if editableText != nil {
                        Button {
                            editingLink = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .ganchoTextButton()
                        .accessibilityLabel(Text("Edit content"))
                        .accessibilityIdentifier("detail-edit-link")
                    }
                }
                Text(verbatim: ClipTextPreview.truncated(parts.text, limit: 2_000))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if parts.decoded != nil || parts.scheme != nil {
                    FlowLayout(spacing: 4) {
                        if let decoded = parts.decoded {
                            metaChip(Text("decoded · \(decoded)"), systemImage: nil)
                        }
                        if let scheme = parts.scheme {
                            metaChip(Text(verbatim: scheme), systemImage: nil)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.08), in: shape)
            .overlay(
                shape.strokeBorder(tint.opacity(0.35), lineWidth: GanchoTokens.Stroke.hairline)
            )
            .clipDragSource(item, model: model, enabled: allowsDragOut)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Color.clear)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("detail-link-hero")
        }
    }

    /// Board and Snippet, quiet under the content; the dock holds the rest.
    var actionsSection: some View {
        Section {
            HStack(spacing: GanchoTokens.Spacing.xs) {
                Button {
                    showMoveSheet = true
                } label: {
                    quietAction("Board", systemImage: "rectangle.stack")
                }
                .accessibilityIdentifier("detail-board")
                if isTextLike { snippetButton }
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    /// Off for masked clips, shown as set once the clip is a snippet.
    private var snippetButton: some View {
        let applies = !requiresMasking && !isSnippet
        return Button {
            Task { if await model.saveAsSnippet(item) { isSnippet = true } }
        } label: {
            quietAction("Snippet", systemImage: isSnippet ? "text.badge.checkmark" : "textformat")
                .opacity(applies ? 1 : ButtonStates.disabledOpacity)
        }
        .disabled(!applies)
        .accessibilityValue(isSnippet ? Text("Saved") : Text(verbatim: ""))
        .accessibilityIdentifier("detail-save-snippet")
    }

    private func quietAction(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, GanchoTokens.Spacing.sm)
            .frame(minHeight: 36)
            .ganchoChip(selected: false)
            .contentShape(Capsule())
    }

    /// The boards this clip is on, and + Add.
    var boardsSection: some View {
        Section("Boards") {
            FlowLayout(spacing: 6) {
                ForEach(currentBoards) { board in
                    HStack(spacing: 5) {
                        BoardDot(board: board, size: 9)
                        board.displayTitle
                    }
                    .font(.subheadline)
                    .padding(.horizontal, GanchoTokens.Spacing.sm)
                    .frame(minHeight: 30)
                    .background(.quaternary, in: Capsule())
                }
                Button {
                    showMoveSheet = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline)
                        .padding(.horizontal, GanchoTokens.Spacing.sm)
                        .frame(minHeight: 30)
                        .background(.quaternary, in: Capsule())
                        .foregroundStyle(GanchoTokens.Palette.ink2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Add to board"))
                .accessibilityIdentifier("detail-add-to-board")
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    /// The board this clip seems to belong on: adds on tap, dismisses with its ×.
    func suggestionRow(_ board: Pinboard) -> some View {
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.lg, style: .continuous)
        return Section {
            HStack(spacing: GanchoTokens.Spacing.xs) {
                Button {
                    Task {
                        guard await model.setBoardMembership(item, board: board, member: true)
                        else { return }
                        boardIDs = await model.boardMembership(for: item)
                        suggestedBoard = nil
                    }
                } label: {
                    Label {
                        Text("Add to \(board.name)? \(Text("Add").bold())")
                    } icon: {
                        Image(systemName: "tray")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                Button {
                    suggestedBoard = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .frame(
                            minWidth: GanchoTokens.HitTarget.touch,
                            minHeight: GanchoTokens.HitTarget.touch)
                }
                .accessibilityLabel(Text("Dismiss"))
            }
            .buttonStyle(.plain)
            .font(.subheadline)
            .foregroundStyle(GanchoTokens.Palette.ink2)
            .padding(.leading, GanchoTokens.Spacing.sm)
            .background(GanchoTokens.Palette.controlFill, in: shape)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("board-suggestion")
        }
    }

    func metaChip(_ text: Text, systemImage: String?) -> some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.caption2) }
            text.font(.caption)
        }
        .padding(.horizontal, GanchoTokens.Spacing.xs)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
        .foregroundStyle(.secondary)
    }
}
