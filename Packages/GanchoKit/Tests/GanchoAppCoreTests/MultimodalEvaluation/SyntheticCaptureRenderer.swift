import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Draws corpus scenes into PNG bytes with CoreGraphics and CoreText only, so the
/// same scene renders identically on every run of one machine.
enum SyntheticCaptureRenderer {
    static let size = CGSize(width: 1_000, height: 640)

    enum RenderError: Error { case textScene, contextUnavailable, encodingFailed }

    static func png(for scene: MultimodalEvaluationCorpus.Scene) throws -> Data {
        guard scene.isImage else { throw RenderError.textScene }
        guard
            let context = CGContext(
                data: nil, width: Int(size.width), height: Int(size.height),
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw RenderError.contextUnavailable }
        // Every drawing helper below takes top-left coordinates, like a screenshot.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        fill(CGRect(origin: .zero, size: size), white, in: context)

        switch scene {
        case .dialog(let title, let message, let code):
            drawDialog(title: title, message: message, code: code, in: context)
        case .diagram(let nodes):
            drawDiagram(nodes, in: context)
        case .barChart(let title, let labels, let values):
            drawChart(title: title, labels: labels, values: values, in: context)
        case .statusScreen(let title, let lines):
            drawText(title, size: 44, bold: true, at: CGPoint(x: 80, y: 80), in: context)
            for (index, line) in lines.enumerated() {
                drawText(
                    line, size: 36, at: CGPoint(x: 80, y: 200 + CGFloat(index) * 90), in: context)
            }
        case .shapes(let shapes):
            for shape in shapes { draw(shape, in: context) }
        case .text:
            throw RenderError.textScene
        }
        return try encode(context)
    }

    // MARK: - Scenes

    private static func drawDialog(
        title: String, message: String, code: String, in context: CGContext
    ) {
        fill(CGRect(origin: .zero, size: size), CGColor(gray: 0.9, alpha: 1), in: context)
        let panel = CGRect(x: 100, y: 100, width: 800, height: 440)
        fill(panel, white, in: context)
        context.setStrokeColor(black)
        context.setLineWidth(2)
        context.stroke(panel)
        drawText(title, size: 44, bold: true, at: CGPoint(x: 140, y: 150), in: context)
        drawWrapped(
            message, size: 32, in: CGRect(x: 140, y: 240, width: 720, height: 160),
            context: context)
        drawText(code, size: 40, at: CGPoint(x: 140, y: 440), in: context)
    }

    private static func drawDiagram(_ nodes: [String], in context: CGContext) {
        let boxSize = CGSize(width: 240, height: 120)
        let gap = (size.width - CGFloat(nodes.count) * boxSize.width) / CGFloat(nodes.count + 1)
        let top = (size.height - boxSize.height) / 2
        let boxes = nodes.indices.map { index in
            CGRect(
                x: gap + CGFloat(index) * (boxSize.width + gap), y: top,
                width: boxSize.width, height: boxSize.height)
        }
        context.setStrokeColor(black)
        context.setLineWidth(4)
        for (label, box) in zip(nodes, boxes) {
            context.stroke(box)
            drawText(label, size: 32, centeredIn: box, in: context)
        }
        for (from, to) in zip(boxes, boxes.dropFirst()) {
            drawArrow(
                from: CGPoint(x: from.maxX + 12, y: from.midY),
                to: CGPoint(x: to.minX - 12, y: to.midY), in: context)
        }
    }

    private static func drawChart(
        title: String, labels: [String], values: [Double], in context: CGContext
    ) {
        drawText(title, size: 40, bold: true, at: CGPoint(x: 80, y: 60), in: context)
        let baseline: CGFloat = 520
        let maximum = values.max() ?? 1
        let slot = (size.width - 160) / CGFloat(values.count)
        context.setStrokeColor(black)
        context.setLineWidth(3)
        context.strokeLineSegments(between: [
            CGPoint(x: 80, y: baseline), CGPoint(x: size.width - 80, y: baseline)
        ])
        for (index, (label, value)) in zip(labels, values).enumerated() {
            let height = CGFloat(value / maximum) * 340
            let bar = CGRect(
                x: 80 + CGFloat(index) * slot + slot * 0.2, y: baseline - height,
                width: slot * 0.6, height: height)
            fill(bar, CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1), in: context)
            drawText(
                label, size: 30,
                centeredIn: CGRect(x: bar.minX, y: baseline + 16, width: bar.width, height: 48),
                in: context)
        }
    }

    private static func draw(_ shape: MultimodalEvaluationCorpus.Shape, in context: CGContext) {
        let rect = CGRect(
            x: shape.frame.minX * size.width, y: shape.frame.minY * size.height,
            width: shape.frame.width * size.height, height: shape.frame.height * size.height)
        context.setFillColor(colour(shape.colour))
        switch shape.kind {
        case .circle:
            context.fillEllipse(in: rect)
        case .square:
            context.fill(rect)
        case .triangle:
            context.beginPath()
            context.move(to: CGPoint(x: rect.midX, y: rect.minY))
            context.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            context.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            context.closePath()
            context.fillPath()
        }
    }

    // MARK: - Primitives

    private static let white = CGColor(gray: 1, alpha: 1)
    private static let black = CGColor(gray: 0, alpha: 1)

    private static func colour(_ colour: MultimodalEvaluationCorpus.Colour) -> CGColor {
        switch colour {
        case .red: CGColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1)
        case .blue: CGColor(red: 0.1, green: 0.3, blue: 0.85, alpha: 1)
        case .green: CGColor(red: 0.1, green: 0.65, blue: 0.2, alpha: 1)
        case .yellow: CGColor(red: 0.95, green: 0.8, blue: 0.1, alpha: 1)
        case .purple: CGColor(red: 0.5, green: 0.2, blue: 0.7, alpha: 1)
        case .orange: CGColor(red: 0.95, green: 0.5, blue: 0.1, alpha: 1)
        }
    }

    private static func fill(_ rect: CGRect, _ colour: CGColor, in context: CGContext) {
        context.setFillColor(colour)
        context.fill(rect)
    }

    private static func drawArrow(from start: CGPoint, to end: CGPoint, in context: CGContext) {
        context.strokeLineSegments(between: [start, CGPoint(x: end.x - 16, y: end.y)])
        context.setFillColor(black)
        context.beginPath()
        context.move(to: end)
        context.addLine(to: CGPoint(x: end.x - 22, y: end.y - 14))
        context.addLine(to: CGPoint(x: end.x - 22, y: end.y + 14))
        context.closePath()
        context.fillPath()
    }

    private static func attributed(
        _ text: String, size: CGFloat, bold: Bool
    )
        -> NSAttributedString
    {
        let font = CTFontCreateWithName(
            (bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
        return NSAttributedString(
            string: text,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): black
            ])
    }

    /// `point` is the top-left corner of the line box.
    private static func drawText(
        _ text: String, size: CGFloat, bold: Bool = false, at point: CGPoint,
        in context: CGContext
    ) {
        let line = CTLineCreateWithAttributedString(attributed(text, size: size, bold: bold))
        drawLine(line, at: CGPoint(x: point.x, y: point.y + size), in: context)
    }

    private static func drawText(
        _ text: String, size: CGFloat, centeredIn rect: CGRect, in context: CGContext
    ) {
        let line = CTLineCreateWithAttributedString(attributed(text, size: size, bold: false))
        let bounds = CTLineGetTypographicBounds(line, nil, nil, nil)
        let origin = CGPoint(x: rect.midX - CGFloat(bounds) / 2, y: rect.midY + size * 0.35)
        drawLine(line, at: origin, in: context)
    }

    /// CoreText draws upward from a baseline, so un-flip around it for each line.
    private static func drawLine(_ line: CTLine, at baseline: CGPoint, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: baseline.x, y: baseline.y)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static func drawWrapped(
        _ text: String, size: CGFloat, in rect: CGRect, context: CGContext
    ) {
        let setter = CTFramesetterCreateWithAttributedString(
            attributed(text, size: size, bold: false))
        let frame = CTFramesetterCreateFrame(
            setter, CFRange(location: 0, length: 0),
            CGPath(rect: CGRect(origin: .zero, size: rect.size), transform: nil), nil)
        let lines = CTFrameGetLines(frame) as? [CTLine] ?? []
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        for (line, origin) in zip(lines, origins) {
            // Frame origins are bottom-up within `rect`; convert to the flipped canvas.
            let baseline = CGPoint(x: rect.minX + origin.x, y: rect.maxY - origin.y)
            drawLine(line, at: baseline, in: context)
        }
    }

    private static func encode(_ context: CGContext) throws -> Data {
        guard let image = context.makeImage() else { throw RenderError.encodingFailed }
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, UTType.png.identifier as CFString, 1, nil)
        else { throw RenderError.encodingFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw RenderError.encodingFailed }
        return output as Data
    }
}
