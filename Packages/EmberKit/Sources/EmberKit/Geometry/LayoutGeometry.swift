import CoreGraphics

// MARK: - Toolbar placement

/// Places toolbar buttons around the capture selection the way Flameshot's
/// `ButtonHandler` does: rings of buttons wrap the selection clockwise
/// (row below → column right → row above → column left), each ring one button
/// further out, and when no side has room the buttons go inside the selection.
public enum ToolbarLayout {
    /// - Returns: one button **centre** per button, in the same space as
    ///   `selection` and `bounds`.
    public static func centers(
        count: Int,
        selection: CGRect,
        bounds: CGRect,
        buttonSize: CGFloat,
        spacing: CGFloat
    ) -> [CGPoint] {
        guard count > 0 else { return [] }
        let pitch = buttonSize + spacing
        let reach = spacing * 2 + buttonSize
        var area = minimumSized(selection.standardized, size: buttonSize).intersection(bounds)
        var result: [CGPoint] = []

        for _ in 0..<32 where result.count < count {
            let blockedBottom = area.maxY + reach > bounds.maxY
            let blockedTop = area.minY - reach < bounds.minY
            let blockedRight = area.maxX + reach > bounds.maxX
            let blockedLeft = area.minX - reach < bounds.minX
            if blockedBottom && blockedTop && blockedLeft && blockedRight { break }

            let perRow = max(Int((area.width + spacing) / pitch), 1)
            let perCol = max(Int((area.height + spacing) / pitch), 1)
            let remainingBefore = count - result.count
            // Up to two extra buttons per row may overhang the corners.
            let maxExtra = (blockedLeft && blockedRight) ? 0 : ((blockedLeft || blockedRight) ? 1 : 2)
            let extras = min(max(remainingBefore - (perRow + perCol) * 2, 0), 4)
            let topExtra = min(extras, maxExtra)
            let bottomExtra = min(extras - topExtra, maxExtra)

            func take(_ n: Int) -> Int { min(n, count - result.count) }

            if !blockedBottom {
                let n = take(perRow + bottomExtra)
                let y = area.maxY + spacing + buttonSize / 2
                result += row(n, centerX: area.midX, y: y, pitch: pitch, leftToRight: true)
            }
            if !blockedRight, result.count < count {
                let n = take(perCol)
                let x = area.maxX + spacing + buttonSize / 2
                result += column(n, x: x, centerY: area.midY, pitch: pitch, topToBottom: false)
            }
            if !blockedTop, result.count < count {
                let n = take(perRow + topExtra)
                let y = area.minY - spacing - buttonSize / 2
                result += row(n, centerX: area.midX, y: y, pitch: pitch, leftToRight: false)
            }
            if !blockedLeft, result.count < count {
                let n = take(perCol)
                let x = area.minX - spacing - buttonSize / 2
                result += column(n, x: x, centerY: area.midY, pitch: pitch, topToBottom: true)
            }
            area = area.insetBy(dx: -pitch, dy: -pitch).intersection(bounds)
        }

        if result.count < count {
            result += inside(count - result.count, selection: selection.standardized, bounds: bounds, buttonSize: buttonSize, pitch: pitch)
        }
        return result
    }

    private static func minimumSized(_ r: CGRect, size: CGFloat) -> CGRect {
        r.insetBy(dx: min((r.width - size) / 2, 0), dy: min((r.height - size) / 2, 0))
    }

    private static func row(_ n: Int, centerX: CGFloat, y: CGFloat, pitch: CGFloat, leftToRight: Bool) -> [CGPoint] {
        guard n > 0 else { return [] }
        let start = centerX - CGFloat(n - 1) * pitch / 2
        let xs = (0..<n).map { start + CGFloat($0) * pitch }
        return (leftToRight ? xs : xs.reversed()).map { CGPoint(x: $0, y: y) }
    }

    private static func column(_ n: Int, x: CGFloat, centerY: CGFloat, pitch: CGFloat, topToBottom: Bool) -> [CGPoint] {
        guard n > 0 else { return [] }
        let start = centerY - CGFloat(n - 1) * pitch / 2
        let ys = (0..<n).map { start + CGFloat($0) * pitch }
        return (topToBottom ? ys : ys.reversed()).map { CGPoint(x: x, y: $0) }
    }

    /// Rows from the bottom of the selection upward (selection covers the screen).
    private static func inside(_ n: Int, selection: CGRect, bounds: CGRect, buttonSize: CGFloat, pitch: CGFloat) -> [CGPoint] {
        let area = selection.intersection(bounds).insetBy(dx: pitch / 2, dy: pitch / 2)
        let perRow = max(Int(max(area.width, 0) / pitch) + 1, 1)
        var result: [CGPoint] = []
        var y = (area.isNull ? bounds.maxY - pitch : area.maxY)
        while result.count < n {
            let k = min(perRow, n - result.count)
            result += row(k, centerX: selection.midX, y: y, pitch: pitch, leftToRight: true)
            y -= pitch
        }
        return result
    }
}

// MARK: - Radial colour picker

/// Swatches on a circle starting at 12 o'clock and going counter-clockwise,
/// like Flameshot's right-click colour wheel.
public enum RadialLayout {
    public static func radius(count: Int, buttonSize: CGFloat) -> CGFloat {
        3 * CGFloat(count) + buttonSize
    }

    public static func swatchSize(buttonSize: CGFloat) -> CGFloat { buttonSize * 0.6 }

    public static func centers(count: Int, around center: CGPoint, radius: CGFloat) -> [CGPoint] {
        guard count > 0 else { return [] }
        return (0..<count).map { i in
            let angle = CGFloat.pi / 2 + CGFloat(i) * 2 * .pi / CGFloat(count)
            return CGPoint(x: center.x + cos(angle) * radius, y: center.y - sin(angle) * radius)
        }
    }

    /// Swatch the finger points at. Near the centre nothing is chosen, so
    /// lifting without moving keeps the current colour.
    public static func index(at point: CGPoint, count: Int, around center: CGPoint, radius: CGFloat) -> Int? {
        guard count > 0, point.distance(to: center) > radius * 0.35 else { return nil }
        let angle = atan2(-(point.y - center.y), point.x - center.x) - .pi / 2
        let step = 2 * CGFloat.pi / CGFloat(count)
        let i = Int((angle / step).rounded())
        return ((i % count) + count) % count
    }
}

// MARK: - Viewport

/// Aspect-fit mapping between the screenshot (image pixels) and the view
/// (points). The model works in image pixels; views convert at the edges.
public struct ViewportMapping: Equatable, Sendable {
    public var imageSize: CGSize
    public var viewSize: CGSize

    public init(imageSize: CGSize, viewSize: CGSize) {
        self.imageSize = imageSize
        self.viewSize = viewSize
    }

    /// View points per image pixel.
    public var scale: CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
    }

    public var origin: CGPoint {
        CGPoint(x: (viewSize.width - imageSize.width * scale) / 2,
                y: (viewSize.height - imageSize.height * scale) / 2)
    }

    /// Where the image sits in the view.
    public var imageFrame: CGRect {
        CGRect(origin: origin, size: CGSize(width: imageSize.width * scale, height: imageSize.height * scale))
    }

    /// Image → view.
    public var transform: CGAffineTransform {
        CGAffineTransform(translationX: origin.x, y: origin.y).scaledBy(x: scale, y: scale)
    }

    public func toView(_ p: CGPoint) -> CGPoint { p.applying(transform) }
    public func toView(_ r: CGRect) -> CGRect { r.applying(transform) }
    public func toImage(_ p: CGPoint) -> CGPoint { p.applying(transform.inverted()) }
    public func toImage(_ r: CGRect) -> CGRect { r.applying(transform.inverted()) }
}
