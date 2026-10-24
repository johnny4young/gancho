import AppKit
import GanchoDesign
import GanchoKit
import SwiftUI

/// An image clip's stage: the picture with its Live Text regions (or without
/// them), the eyedropper that saves the pixel under a click as a colour clip,
/// and the image's dominant colours.
struct PeekImageStage: View {
    let item: ClipItem
    let thumbnail: Image
    @Binding var hoveredLine: Int?
    @Binding var copiedLine: Int?
    @Binding var revealSecret: Bool
    @Binding var isPickingColor: Bool
    @Environment(AppModel.self) private var model
    @State private var showsRegions = true
    @State private var pushedCrosshair = false

    var body: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            thumbnail
                .resizable()
                .scaledToFit()
                // Overlays sit BEFORE the frame so they take the image's fitted
                // size, which is what both the regions and a click map to.
                .overlay {
                    if showsRegions, !isPickingColor {
                        PeekImageTextRegions(
                            item: item, hoveredLine: $hoveredLine, copiedLine: $copiedLine,
                            revealSecret: $revealSecret)
                    }
                }
                .overlay { if isPickingColor { eyedropperLayer } }
                .frame(maxWidth: .infinity, maxHeight: 240)
                .clipShape(
                    RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
                )
                .overlay(alignment: .topTrailing) { stageControls }
                // Dragging the preview itself hands the full-resolution image
                // (not the thumbnail) to the drop target.
                .clipDragSource(item)
            dominantColors
        }
    }

    private var stageControls: some View {
        HStack(spacing: GanchoTokens.Spacing.xxs) {
            Picker("Image view", selection: $showsRegions) {
                Text("Regions").tag(true)
                Text("Image only").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("peek-region-toggle")
            Toggle(isOn: $isPickingColor) {
                Label("Pick color · I", systemImage: "eyedropper")
            }
            .toggleStyle(.button)
            .ganchoInkTint()
            .controlSize(.small)
            .accessibilityIdentifier("peek-pick-color")
        }
        .panelFont(.caption)
        .padding(GanchoTokens.Spacing.xxs)
        // The controls sit over arbitrary pixels; a near-opaque backing keeps them legible.
        .background(
            .background.opacity(0.92), in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .padding(GanchoTokens.Spacing.xs)
    }

    /// A click anywhere on the image saves that pixel; the cursor says so.
    private var eyedropperLayer: some View {
        GeometryReader { geometry in
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { location in
                    pick(at: location, in: geometry.size)
                }
                .onHover { inside in
                    guard inside != pushedCrosshair else { return }
                    pushedCrosshair = inside
                    if inside { NSCursor.crosshair.push() } else { NSCursor.pop() }
                }
        }
        // A pick removes the layer under the pointer, so no hover exit arrives.
        .onDisappear {
            if pushedCrosshair { NSCursor.pop() }
            pushedCrosshair = false
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Click the image to save that color"))
        .accessibilityIdentifier("peek-eyedropper")
    }

    private func pick(at location: CGPoint, in size: CGSize) {
        let item = item
        Task { @MainActor in
            guard let color = await model.sampleColor(of: item, at: location, in: size) else {
                return
            }
            isPickingColor = false
            model.saveColorClip(color)
        }
    }

    @ViewBuilder private var dominantColors: some View {
        let palette = model.thumbnails.cachedPalette(for: item)
        if !palette.isEmpty {
            HStack(spacing: GanchoTokens.Spacing.xxs) {
                Image(systemName: "paintpalette").accessibilityHidden(true)
                Text("Dominant ·")
                ForEach(Array(palette.enumerated()), id: \.offset) { index, color in
                    Button {
                        model.saveColorClip(color)
                    } label: {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color(Color.Resolved(color)))
                            .frame(width: 9, height: 9)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .strokeBorder(
                                        .separator, lineWidth: GanchoTokens.Stroke.hairline)
                            )
                            .padding(3)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(Text("Save \(color.hex) as a color clip"))
                    .accessibilityLabel(Text("Save \(color.hex) as a color clip"))
                    .accessibilityIdentifier("peek-dominant-color-\(index)")
                }
            }
            .panelFont(.caption, .semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, GanchoTokens.Spacing.xs)
            .frame(height: 24)
            .background(Color.primary.opacity(0.06), in: Capsule())
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("peek-dominant-colors")
        }
    }
}
