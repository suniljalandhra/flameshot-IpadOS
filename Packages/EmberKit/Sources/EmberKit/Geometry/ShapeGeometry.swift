import CoreGraphics
import Foundation

// MARK: - Snapping

public enum Snapping {
    /// Constrain a drag vector (y grows downward) the way Flameshot does when
    /// Shift is held.
    public static func adjust(_ v: CGVector, mode: SnapMode) -> CGVector {
        switch mode {
        case .none:
            return v
        case .octilinear:
            // Nearest of 4 axes (each covers both directions): 0 = horizontal,
            // 1 = rising diagonal, 2 = vertical, 3 = falling diagonal.
            let angle = atan2(-v.dy, v.dx)
            let dir = positiveModulo(Int((angle / (.pi / 4)).rounded()), 4)
            switch dir {
            case 0: return CGVector(dx: v.dx, dy: 0)
            case 2: return CGVector(dx: 0, dy: v.dy)
            case 1: return risingDiagonal(v)
            default: return fallingDiagonal(v)
            }
        case .square:
            let angle = atan2(-v.dy, v.dx)
            let dir = positiveModulo(Int(((angle - .pi / 4) / (.pi / 2)).rounded()), 2)
            return dir == 0 ? risingDiagonal(v) : fallingDiagonal(v)
        }
    }

    /// Project onto the line y = -x (up-right / down-left on screen).
    private static func risingDiagonal(_ v: CGVector) -> CGVector {
        let x = (v.dx - v.dy) / 2
        return CGVector(dx: x, dy: -x)
    }

    /// Project onto the line y = x (down-right / up-left on screen).
    private static func fallingDiagonal(_ v: CGVector) -> CGVector {
        let x = (v.dx + v.dy) / 2
        return CGVector(dx: x, dy: x)
    }

    private static func positiveModulo(_ a: Int, _ n: Int) -> Int { ((a % n) + n) % n }
}

// MARK: - Arrow

public struct ArrowGeometry {
    /// Logical head length / width before thickness is added (Flameshot: 18 / 10).
    public static let baseHeadLength: CGFloat = 18
    public static let baseHeadWidth: CGFloat = 10

    public var shaftStart: CGPoint
    public var shaftEnd: CGPoint
    /// Filled head, tip at the arrow's end point.
    public var head: CGPath
    /// Curved arrows use a flat cap so the shaft tucks into the notch.
    public var flatCap: Bool

    /// - Parameters:
    ///   - from: tail (press point)
    ///   - to: tip (release point)
    ///   - thickness: logical thickness
    ///   - scale: image pixels per point
    public static func make(from: CGPoint, to: CGPoint, thickness: CGFloat, scale: CGFloat, style: ArrowStyle) -> ArrowGeometry {
        let t = thickness * scale
        let length = from.distance(to: to)
        guard length > 0 else {
            return ArrowGeometry(shaftStart: from, shaftEnd: to, head: CGMutablePath(), flatCap: false)
        }
        let dir = CGVector(dx: (to.x - from.x) / length, dy: (to.y - from.y) / length)
        let normal = CGVector(dx: -dir.dy, dy: dir.dx)
        let fullHead = baseHeadLength * scale + 4 * t
        let halfWidth = (baseHeadWidth * scale + 2 * t) / 2

        // Short arrows: the head shrinks to fit and the shaft nearly vanishes.
        let isShort = length < fullHead - 2 * t
        let headLength = isShort ? length + 2 * t : fullHead
        let baseDistance = max(length + 2 * t - headLength, 0)
        let shaftLength = isShort ? t / 4 : baseDistance
        let baseCenter = from + dir * baseDistance
        let shaftEnd = from + dir * shaftLength

        let left = baseCenter + normal * halfWidth
        let right = baseCenter + normal * -halfWidth
        let path = CGMutablePath()

        switch style {
        case .standard:
            path.move(to: to)
            path.addLine(to: left)
            path.addLine(to: right)
            path.closeSubpath()
            return ArrowGeometry(shaftStart: from, shaftEnd: shaftEnd, head: path, flatCap: false)

        case .curved:
            let notchDepth = min(shaftEnd.distance(to: to) * 0.45, halfWidth)
            let shaftBase = shaftEnd
            let notch = shaftBase + dir * notchDepth
            path.move(to: to)
            path.addLine(to: shaftBase + normal * halfWidth)
            path.addQuadCurve(to: notch, control: shaftBase + normal * (halfWidth * 0.25))
            path.addQuadCurve(to: shaftBase + normal * -halfWidth, control: shaftBase + normal * (-halfWidth * 0.25))
            path.closeSubpath()
            // Overlap the notch by one pixel so no gap shows.
            let end = shaftBase + dir * (notchDepth + scale)
            return ArrowGeometry(shaftStart: from, shaftEnd: end, head: path, flatCap: true)
        }
    }
}

// MARK: - Counter

public enum CounterGeometry {
    /// Logical bubble radius on top of the thickness (Flameshot: 15).
    public static let baseRadius: CGFloat = 15
    /// Extra ring for the outline (Flameshot: 2).
    public static let outlinePadding: CGFloat = 2

    public static func radius(thickness: CGFloat, scale: CGFloat) -> CGFloat {
        (thickness + baseRadius) * scale
    }

    /// The pointer "tail": a kite from the bubble centre to the drag point.
    /// Only drawn when the drag leaves the bubble.
    public static func tail(center: CGPoint, tip: CGPoint, radius: CGFloat) -> CGPath? {
        let length = center.distance(to: tip)
        guard length > radius else { return nil }
        let normal = CGVector(dx: -(tip.y - center.y) / length, dy: (tip.x - center.x) / length) * radius
        let path = CGMutablePath()
        path.move(to: center)
        path.addLine(to: center + normal)
        path.addLine(to: tip)
        path.addLine(to: center + normal * -1)
        path.closeSubpath()
        return path
    }
}

// MARK: - Marker

public enum MarkerGeometry {
    /// Flameshot widens the highlighter by 14 on top of the thickness.
    public static let extraWidth: CGFloat = 14

    public static func width(thickness: CGFloat, scale: CGFloat) -> CGFloat {
        (thickness + extraWidth) * scale
    }
}

// MARK: - Rectangle

public enum RectangleGeometry {
    /// The filled rectangle grows by this many pixels on each side.
    public static func filledOffset(thickness t: CGFloat) -> CGFloat {
        t <= 1 ? 1 : (t / 2 + 0.5).rounded()
    }
}

// MARK: - Selection

/// The 8 resize handles of the capture selection.
public enum SelectionHandle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    public func position(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .top: CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    /// Drag `self` by `delta`; the opposite edge stays put. Returns a
    /// normalised rect clamped to `bounds`, so dragging past the opposite edge
    /// flips the selection like Flameshot does.
    public func resize(_ rect: CGRect, by delta: CGVector, within bounds: CGRect) -> CGRect {
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        switch self {
        case .topLeft: minX += delta.dx; minY += delta.dy
        case .top: minY += delta.dy
        case .topRight: maxX += delta.dx; minY += delta.dy
        case .right: maxX += delta.dx
        case .bottomRight: maxX += delta.dx; maxY += delta.dy
        case .bottom: maxY += delta.dy
        case .bottomLeft: minX += delta.dx; maxY += delta.dy
        case .left: minX += delta.dx
        }
        let r = CGRect(corner: CGPoint(x: minX, y: minY), opposite: CGPoint(x: maxX, y: maxY))
        return r.intersection(bounds).standardized
    }

    /// The handle under `point`, if any.
    public static func hit(_ point: CGPoint, in rect: CGRect, tolerance: CGFloat) -> SelectionHandle? {
        allCases
            .map { ($0, $0.position(in: rect).distance(to: point)) }
            .filter { $0.1 <= tolerance }
            .min { $0.1 < $1.1 }?
            .0
    }
}

public extension CGRect {
    /// Move a rect by `delta` but keep it fully inside `bounds`.
    func moved(by delta: CGVector, within bounds: CGRect) -> CGRect {
        var r = offsetBy(dx: delta.dx, dy: delta.dy)
        r.origin.x = min(max(r.origin.x, bounds.minX), bounds.maxX - r.width)
        r.origin.y = min(max(r.origin.y, bounds.minY), bounds.maxY - r.height)
        return r
    }
}
