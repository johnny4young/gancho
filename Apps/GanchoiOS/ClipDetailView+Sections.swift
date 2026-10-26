import GanchoAI
import GanchoDesign
import GanchoKit
import SwiftUI
import UIKit

extension ClipDetailView {
    /// Kind, source app, device and age — where the clip came from, first.
    var provenanceRow: some View {
        Section {
            FlowLayout(spacing: 6) {
                let tint = GanchoTokens.Palette.kindTint(for: item.kind)
                Label {
                    Text(LocalizedStringKey(item.kind.rawValue))
                } icon: {
                    Image(systemName: item.kind.symbolName)
                }
                .font(.caption.weight(.bold))
                .padding(.horizontal, GanchoTokens.Spacing.xs)
                .padding(.vertical, 3)
                .ganchoTintedPill(tint, wash: 0.16)
                if requiresMasking {
                    metaChip(Text("Masked"), systemImage: "lock.fill")
                }
                if let bundleID = item.sourceAppBundleID, !bundleID.isEmpty {
                    metaChip(
                        Text(verbatim: SourceApp.fallbackName(forBundleID: bundleID)),
                        systemImage: "app.dashed")
                }
                if let device = item.sourceDeviceName, !device.isEmpty {
                    metaChip(Text(verbatim: device), systemImage: "desktopcomputer")
                }
                metaChip(
                    Text(.currentDate, format: .reference(to: item.createdAt, maxFieldCount: 1)),
                    systemImage: "clock")
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Color.clear)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("detail-provenance")
        }
    }

    /// A link as itself: its host large, the full URL, and what decoding and
    /// the scheme add. A tint and a full outline mark it, never a side bar.
    func linkHero(_ parts: ClipLinkParts) -> some View {
        let tint = GanchoTokens.Palette.kindTint(for: .url)
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.lg, style: .continuous)
        return Section {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: parts.host)
                        .font(.title2.weight(.heavy))
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
            .contentShape(.dragPreview, shape)
            .clipDragSource(item, model: model, enabled: allowsDragOut)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Color.clear)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("detail-link-hero")
        }
    }

    /// Copy is the one primary: iOS can't paste into another app, so copying
    /// for the user to paste is the realizable path. Then the four others.
    var actionsSection: some View {
        Section {
            VStack(spacing: GanchoTokens.Spacing.xs) {
                Button {
                    Task { await model.copyToPasteboard(item) }
                    dismiss()
                } label: {
                    HStack(spacing: GanchoTokens.Spacing.xs) {
                        Label("Copy", systemImage: "doc.on.clipboard")
                        if showsCopyShortcut {
                            KeyChip(keys: "⌘⏎", onFill: true).accessibilityHidden(true)
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        GanchoTokens.Palette.accent,
                        in: RoundedRectangle(
                            cornerRadius: GanchoTokens.Radius.lg, style: .continuous)
                    )
                    .foregroundStyle(ContrastingForeground(on: GanchoTokens.Palette.accent))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("detail-copy")
                HStack(spacing: 10) {
                    ShareLink(item: model.shareItem(for: item), preview: SharePreview("Gancho")) {
                        actionLabel("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                    .disabled(!ClipSafeDelivery.isEligible(item))
                    actionButton(
                        item.isPinned ? "Pinned" : "Pin",
                        systemImage: item.isPinned ? "pin.fill" : "pin"
                    ) {
                        Task { await model.togglePin(item) }
                    }
                    actionButton("Board", systemImage: "rectangle.stack") { showMoveSheet = true }
                        .accessibilityIdentifier("detail-board")
                    snippetButton
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    /// Always in the row so it never jumps: off for non-text and masked clips,
    /// shown as set once the clip is a snippet.
    private var snippetButton: some View {
        let applies = isTextLike && !requiresMasking
        return actionButton(
            "Snippet",
            systemImage: isSnippet ? "text.badge.checkmark" : "textformat"
        ) {
            Task { if await model.saveAsSnippet(item) { isSnippet = true } }
        }
        .disabled(!applies || isSnippet)
        .accessibilityValue(isSnippet ? Text("Saved") : Text(verbatim: ""))
        .accessibilityIdentifier("detail-save-snippet")
    }

    private func actionButton(
        _ title: LocalizedStringKey, systemImage: String, _ run: @escaping () -> Void
    ) -> some View {
        Button(action: run) { actionLabel(title, systemImage: systemImage) }
            .buttonStyle(.plain)
    }

    private func actionLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 20))
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(
                    .quaternary,
                    in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
                )
                .foregroundStyle(.primary)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// The boards this clip is on, + Add, and the auto-board suggestion as a
    /// chip that adds on tap and dismisses with its ×.
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
                        .foregroundStyle(GanchoTokens.Palette.accentInk)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Add to board"))
                .accessibilityIdentifier("detail-add-to-board")
                if let board = suggestedBoard { suggestionChip(board) }
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    private func suggestionChip(_ board: Pinboard) -> some View {
        HStack(spacing: 6) {
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
                    Image(systemName: "sparkles")
                }
            }
            .buttonStyle(.plain)
            Button {
                suggestedBoard = nil
            } label: {
                Image(systemName: "xmark").font(.caption2.weight(.bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Dismiss"))
        }
        .font(.subheadline)
        .foregroundStyle(GanchoTokens.Palette.accentInk)
        .padding(.horizontal, GanchoTokens.Spacing.sm)
        .frame(minHeight: 30)
        .background(GanchoTokens.Palette.accentTint, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("board-suggestion")
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
