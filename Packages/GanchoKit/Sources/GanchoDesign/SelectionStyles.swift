import SwiftUI

extension View {
    /// A chip with a resting fill: the control fill at rest, an inverse fill
    /// when selected, so the two never read as the same grey.
    public func ganchoChip(selected: Bool, in shape: some Shape = Capsule()) -> some View {
        foregroundStyle(selected ? GanchoTokens.Palette.inverseText : GanchoTokens.Palette.ink)
            .background(
                selected ? GanchoTokens.Palette.inverseFill : GanchoTokens.Palette.controlFill,
                in: shape)
    }

    /// A tab or row with no resting fill: ink on the selection wash when
    /// selected, `idle` text on nothing otherwise.
    public func ganchoTab(
        selected: Bool, idle: some ShapeStyle = HierarchicalShapeStyle.secondary,
        in shape: some Shape = Capsule()
    ) -> some View {
        foregroundStyle(
            selected ? AnyShapeStyle(GanchoTokens.Palette.ink) : AnyShapeStyle(idle)
        )
        .background(selected ? GanchoTokens.Palette.selectionWash : Color.clear, in: shape)
    }

    /// A small label or tile that must stand out without the accent: inverse
    /// text on an inverse fill.
    public func ganchoInverseBadge(in shape: some Shape = Capsule()) -> some View {
        foregroundStyle(GanchoTokens.Palette.inverseText)
            .background(GanchoTokens.Palette.inverseFill, in: shape)
    }
}
