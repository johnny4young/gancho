import CoreGraphics

/// AppKit's global points are bottom-up; ScreenCaptureKit display space is
/// top-down. Do not multiply by backingScaleFactor: captureImage(in:) takes
/// points and performs its own display-scale conversion.
public enum ScreenTextRegion {
    public static func selection(
        from start: CGPoint, to end: CGPoint, display: CGRect, primaryDisplayTop: CGFloat
    ) -> CGRect? {
        // `intersection(display)` is what keeps a drag on its starting
        // display — it is load-bearing, not a tidy-up. Clamping `end` to the
        // display first would change nothing (for an axis-aligned box the two
        // compose to the same rect), which is exactly why it must not be
        // mistaken for the mechanism and this line removed as redundant.
        let selected = CGRect(
            x: min(start.x, end.x), y: min(start.y, end.y),
            width: abs(end.x - start.x), height: abs(end.y - start.y)
        ).intersection(display)
        guard !selected.isNull, selected.width >= 2, selected.height >= 2 else { return nil }
        return CGRect(
            x: selected.minX, y: primaryDisplayTop - selected.maxY, width: selected.width,
            height: selected.height)
    }
}
