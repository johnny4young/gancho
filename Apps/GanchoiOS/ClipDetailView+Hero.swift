import GanchoDesign
import GanchoKit
import SwiftUI
import UIKit

extension ClipDetailView {
    /// The content as the stage: a colour fills the top with its value, an
    /// image with its picture. Both run under the bar; other kinds have none.
    @ViewBuilder func hero(maxHeight: CGFloat) -> some View {
        if let colorValue {
            let fill = Color(Color.Resolved(colorValue))
            VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xxs) {
                provenanceCaption
                Text(verbatim: colorValue.hex)
                    .font(
                        GanchoType.font(.ui, size: 44, weight: .semibold, relativeTo: .largeTitle)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
            }
            .foregroundStyle(ContrastingForeground(on: fill))
            .padding(GanchoTokens.Spacing.md)
            .frame(
                maxWidth: .infinity, minHeight: 120, maxHeight: max(120, maxHeight),
                alignment: .bottomLeading
            )
            .background(fill.ignoresSafeArea(edges: .top))
            .clipDragSource(item, model: model, enabled: allowsDragOut)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("detail-color-hero")
        } else if let heroImage {
            heroImage
                .resizable()
                .scaledToFit()
                .overlay {
                    ClipImageTextRegions(
                        item: item, revealed: ocrRevealed, copiedLine: ocrCopiedLine,
                        links: ocrLinks, onLine: tapRecognizedLine)
                }
                .frame(maxWidth: .infinity, maxHeight: min(340, maxHeight))
                .background(GanchoTokens.Palette.controlFill.ignoresSafeArea(edges: .top))
                .contentShape(Rectangle())
                .clipDragSource(item, model: model, enabled: allowsDragOut)
                .onTapGesture { showFullImage = true }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(Text("Open full screen to zoom"))
        }
    }

    /// Each notation of the colour as a row that copies it.
    func colorFormats(_ value: ColorValue) -> some View {
        let formats = [
            ("HEX", value.hex), ("RGB", value.rgb), ("HSL", value.hsl), ("SWIFTUI", value.swift)
        ]
        return Section {
            ForEach(formats, id: \.0) { name, text in
                Button {
                    UIPasteboard.general.string = text
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    HStack(spacing: GanchoTokens.Spacing.sm) {
                        Text(verbatim: name)
                            .font(dataFont(11, .caption2, weight: .medium))
                            .tracking(0.8)
                            .foregroundStyle(GanchoTokens.Palette.ink3)
                            .frame(width: 64, alignment: .leading)
                        Text(verbatim: text)
                            .font(dataFont(15, .callout))
                            .foregroundStyle(GanchoTokens.Palette.ink)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                        Image(systemName: "square.on.square")
                            .foregroundStyle(GanchoTokens.Palette.ink3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Copy \(name)"))
                .accessibilityValue(Text(verbatim: text))
                .accessibilityIdentifier("detail-format-\(name.lowercased())")
            }
        }
    }

    func dataFont(
        _ size: CGFloat, _ style: Font.TextStyle, weight: Font.Weight = .regular
    ) -> Font {
        GanchoType.font(.data, size: size, weight: weight, relativeTo: style)
    }

    /// Docked under every detail: Copy is the one accent, because iOS can't
    /// paste into another app; Pin, Share and Delete sit beside it, quiet.
    var actionBar: some View {
        HStack(spacing: GanchoTokens.Spacing.sm) {
            Button {
                Task { await model.copyToPasteboard(item) }
                dismiss()
            } label: {
                HStack(spacing: GanchoTokens.Spacing.xs) {
                    if item.kind == .image {
                        Label("Copy image", systemImage: "square.on.square")
                    } else {
                        Label("Copy", systemImage: "square.on.square")
                    }
                    if showsCopyShortcut {
                        KeyCap("⌘⏎", role: .onAccent).accessibilityHidden(true)
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
                .ganchoPrimaryVerb(in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("detail-copy")
            HStack(spacing: 0) {
                Button {
                    Task { await model.togglePin(item) }
                } label: {
                    barIcon(item.isPinned ? "pin.fill" : "pin")
                }
                .accessibilityLabel(item.isPinned ? Text("Pinned") : Text("Pin"))
                .accessibilityIdentifier("detail-pin")
                ShareLink(item: model.shareItem(for: item), preview: SharePreview("Gancho")) {
                    barIcon("square.and.arrow.up")
                }
                .disabled(!ClipSafeDelivery.isEligible(item))
                .accessibilityLabel(Text("Share"))
                .accessibilityIdentifier("detail-share")
                Button {
                    Task { await model.delete(item) }
                    dismiss()
                } label: {
                    barIcon("trash").foregroundStyle(GanchoTokens.Palette.danger)
                }
                .accessibilityLabel(Text("Delete"))
                .accessibilityIdentifier("detail-delete")
            }
            .buttonStyle(.plain)
            .foregroundStyle(GanchoTokens.Palette.ink)
            .padding(.horizontal, GanchoTokens.Spacing.xxs)
            .background(GanchoTokens.Palette.controlFill, in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    GanchoTokens.Palette.hairline, lineWidth: GanchoTokens.Stroke.hairline))
        }
        .padding(.horizontal, GanchoTokens.Spacing.md)
        .padding(.vertical, GanchoTokens.Spacing.xs)
        .background(.bar)
    }

    private func barIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.body.weight(.medium))
            .frame(width: GanchoTokens.HitTarget.touch, height: 50)
            .contentShape(Rectangle())
    }
}
