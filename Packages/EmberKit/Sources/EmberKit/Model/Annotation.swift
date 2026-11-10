import CoreGraphics
import Foundation

/// One finished (or in-progress) mark on the screenshot.
///
/// All coordinates are in **image pixels** of the frozen screenshot. Sizes are
/// stored in Flameshot's logical units (points) together with `scale`, the
/// number of image pixels per point, so a "thickness 3" line looks the same on a
/// 1×, 2× or 3× capture.
public struct Annotation: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var kind: ToolKind
    /// Pencil: every sampled point. Text: `[origin]`. Others: `[first, second]`.
    public var points: [CGPoint]
    public var color: RGBAColor
    /// Thickness, or font size for text. Logical points.
    public var size: CGFloat
    /// Image pixels per logical point.
    public var scale: CGFloat
    public var text: String
    /// Counter value.
    public var number: Int
    public var arrowStyle: ArrowStyle
    public var counterOutline: Bool
    public var securePixelate: Bool

    public init(
        id: UUID = UUID(),
        kind: ToolKind,
        points: [CGPoint],
        color: RGBAColor,
        size: CGFloat,
        scale: CGFloat = 1,
        text: String = "",
        number: Int = 0,
        arrowStyle: ArrowStyle = .standard,
        counterOutline: Bool = true,
        securePixelate: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.points = points
        self.color = color
        self.size = size
        self.scale = scale
        self.text = text
        self.number = number
        self.arrowStyle = arrowStyle
        self.counterOutline = counterOutline
        self.securePixelate = securePixelate
    }

    public var first: CGPoint { points.first ?? .zero }
    public var second: CGPoint { points.count > 1 ? points[points.count - 1] : first }

    /// Size in image pixels.
    public var pixelSize: CGFloat { size * scale }

    /// Flameshot discards zero-length shapes; counters and text are always
    /// valid once placed (text needs content).
    public var isValid: Bool {
        switch kind {
        case .counter: return !points.isEmpty
        case .text: return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .pencil: return points.count > 1
        case .move: return false
        default: return first != second
        }
    }

    /// Rectangle spanned by the first and last point.
    public var spanRect: CGRect { CGRect(corner: first, opposite: second) }

    /// Area the annotation paints, in image pixels. Used for hit testing and
    /// the selection outline.
    public var boundingRect: CGRect {
        let t = max(pixelSize, 1)
        switch kind {
        case .pencil:
            return CGRect(enclosing: points).insetBy(dx: -t / 2 - 1, dy: -t / 2 - 1)
        case .line, .rectangleOutline, .ellipse:
            return spanRect.insetBy(dx: -t / 2 - 1, dy: -t / 2 - 1)
        case .marker:
            let w = MarkerGeometry.width(thickness: size, scale: scale)
            return spanRect.insetBy(dx: -w / 2 - 1, dy: -w / 2 - 1)
        case .rectangleFilled:
            let offset = RectangleGeometry.filledOffset(thickness: pixelSize)
            return spanRect.insetBy(dx: -offset, dy: -offset)
        case .arrow:
            let head = ArrowGeometry.make(from: first, to: second, thickness: size, scale: scale, style: arrowStyle)
            return spanRect.union(head.head.boundingBoxOfPath).insetBy(dx: -t / 2, dy: -t / 2)
        case .counter:
            let r = CounterGeometry.radius(thickness: size, scale: scale) + CounterGeometry.outlinePadding * scale
            let bubble = CGRect(x: first.x - r, y: first.y - r, width: r * 2, height: r * 2)
            return bubble.union(CGRect(origin: second, size: .zero))
        case .text:
            let box = TextLayout.boxSize(for: text, fontSize: pixelSize, padding: TextLayout.padding * scale)
            return CGRect(origin: first, size: box)
        case .pixelate, .invert:
            return spanRect
        case .move:
            return .null
        }
    }

    /// Hit test with a tolerance in image pixels.
    public func contains(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        boundingRect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
    }

    public func translated(by delta: CGVector) -> Annotation {
        var copy = self
        copy.points = points.map { CGPoint(x: $0.x + delta.dx, y: $0.y + delta.dy) }
        return copy
    }
}

public extension CGRect {
    /// Normalised rect between two corners.
    init(corner a: CGPoint, opposite b: CGPoint) {
        self.init(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// Smallest rect containing all points (`.null` for none).
    init(enclosing points: [CGPoint]) {
        guard let p0 = points.first else {
            self = .null
            return
        }
        var minX = p0.x, maxX = p0.x, minY = p0.y, maxY = p0.y
        for p in points.dropFirst() {
            minX = Swift.min(minX, p.x); maxX = Swift.max(maxX, p.x)
            minY = Swift.min(minY, p.y); maxY = Swift.max(maxY, p.y)
        }
        self.init(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

public extension CGPoint {
    static func - (lhs: CGPoint, rhs: CGPoint) -> CGVector { CGVector(dx: lhs.x - rhs.x, dy: lhs.y - rhs.y) }
    static func + (lhs: CGPoint, rhs: CGVector) -> CGPoint { CGPoint(x: lhs.x + rhs.dx, y: lhs.y + rhs.dy) }
    func distance(to other: CGPoint) -> CGFloat { hypot(x - other.x, y - other.y) }
}

public extension CGVector {
    var length: CGFloat { hypot(dx, dy) }
    static func * (lhs: CGVector, rhs: CGFloat) -> CGVector { CGVector(dx: lhs.dx * rhs, dy: lhs.dy * rhs) }
}
