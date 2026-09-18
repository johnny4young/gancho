import CoreGraphics

/// AppKit's global points are bottom-up; ScreenCaptureKit display space is
/// top-down. Do not multiply by backingScaleFactor: captureImage(in:) takes
/// points and performs its own display-scale conversion.
public enum ScreenTextRegion {
    public static func selection(
        from start: CGPoint, to end: CGPoint, display: CGRect, primaryDisplayTop: CGFloat
    ) -> CGRect? {
        let clamped = CGPoint(
            x: min(max(end.x, display.minX), display.maxX),
            y: min(max(end.y, display.minY), display.maxY))
        let selected = CGRect(
            x: min(start.x, clamped.x), y: min(start.y, clamped.y),
            width: abs(clamped.x - start.x), height: abs(clamped.y - start.y)
        ).intersection(display)
        guard !selected.isNull, selected.width >= 2, selected.height >= 2 else { return nil }
        return CGRect(
            x: selected.minX, y: primaryDisplayTop - selected.maxY, width: selected.width,
            height: selected.height)
    }
}
