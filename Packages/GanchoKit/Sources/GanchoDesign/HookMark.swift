import SwiftUI

/// gancho's hook as a shape, from the brand template's path (viewBox
/// 0.5 9.5 84 84), so any target tints it without an asset of its own.
public struct HookMark: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var hook = Path()
        hook.move(to: CGPoint(x: 50, y: 32))
        hook.addLine(to: CGPoint(x: 50, y: 57))
        hook.addArc(
            center: CGPoint(x: 42.5, y: 69.99), radius: 15,
            startAngle: .degrees(-60), endAngle: .degrees(240), clockwise: false)
        hook.addLine(to: CGPoint(x: 31.5, y: 47.5))
        var mark = hook.strokedPath(StrokeStyle(lineWidth: 13, lineCap: .round, lineJoin: .round))
        mark.addPath(
            Path(ellipseIn: CGRect(x: 42, y: 16, width: 16, height: 16))
                .strokedPath(StrokeStyle(lineWidth: 9)))
        let scale = min(rect.width, rect.height) / 84
        return mark.applying(
            CGAffineTransform(translationX: rect.minX, y: rect.minY)
                .scaledBy(x: scale, y: scale).translatedBy(x: -0.5, y: -9.5))
    }
}
