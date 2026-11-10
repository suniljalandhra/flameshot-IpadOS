import CoreGraphics
import CoreText
import Foundation

/// Draws annotations with CoreGraphics into a **y-down** context whose user
/// space is image pixels. The same renderer drives the live canvas and the
/// export, so what you see is exactly what you get.
public final class AnnotationRenderer: @unchecked Sendable {
    public let baseImage: CGImage

    private let lock = NSLock()
    private var cachedPixels: PixelBuffer?
    private var effectCache: [EffectKey: CGImage] = [:]

    public init(baseImage: CGImage) {
        self.baseImage = baseImage
    }

    public var imageBounds: CGRect { CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height) }

    // MARK: Drawing

    public func draw<S: Sequence>(_ annotations: S, in ctx: CGContext) where S.Element == Annotation {
        for a in annotations { draw(a, in: ctx) }
    }

    public func draw(_ a: Annotation, in ctx: CGContext) {
        guard !a.points.isEmpty else { return }
        let t = a.pixelSize
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setStrokeColor(a.color.cgColor)
        ctx.setFillColor(a.color.cgColor)
        ctx.setLineWidth(max(t, 0.5))

        switch a.kind {
        case .pencil:
            guard a.points.count > 1 else { return }
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.addLines(between: a.points)
            ctx.strokePath()

        case .line:
            ctx.setLineCap(.round)
            ctx.strokeLineSegments(between: [a.first, a.second])

        case .arrow:
            let g = ArrowGeometry.make(from: a.first, to: a.second, thickness: a.size, scale: a.scale, style: a.arrowStyle)
            ctx.setLineCap(g.flatCap ? .butt : .square)
            ctx.strokeLineSegments(between: [g.shaftStart, g.shaftEnd])
            ctx.addPath(g.head)
            ctx.fillPath()

        case .rectangleOutline:
            ctx.setLineCap(.square)
            ctx.setLineJoin(.miter)
            ctx.stroke(a.spanRect)

        case .rectangleFilled:
            if t <= 0 {
                ctx.fill(a.spanRect)
            } else {
                let offset = RectangleGeometry.filledOffset(thickness: t)
                let r = a.spanRect.insetBy(dx: -offset, dy: -offset)
                let radius = min(t, r.width / 2, r.height / 2)
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
                ctx.fillPath()
            }

        case .ellipse:
            ctx.strokeEllipse(in: a.spanRect)

        case .marker:
            ctx.setBlendMode(.multiply)
            ctx.setAlpha(0.35)
            ctx.setLineCap(.square)
            ctx.setLineWidth(MarkerGeometry.width(thickness: a.size, scale: a.scale))
            ctx.strokeLineSegments(between: [a.first, a.second])

        case .text:
            TextLayout.draw(a.text, at: a.first, fontSize: t, padding: TextLayout.padding * a.scale, color: a.color, in: ctx)

        case .counter:
            drawCounter(center: a.first, tip: a.second, number: a.number, color: a.color,
                        radius: CounterGeometry.radius(thickness: a.size, scale: a.scale),
                        scale: a.scale, outline: a.counterOutline, in: ctx)

        case .pixelate, .invert:
            drawEffect(a, in: ctx)

        case .move:
            break
        }
    }

    private func drawCounter(center: CGPoint, tip: CGPoint, number: Int, color: RGBAColor,
                             radius r: CGFloat, scale: CGFloat, outline: Bool, in ctx: CGContext) {
        if let tail = CounterGeometry.tail(center: center, tip: tip, radius: r) {
            ctx.addPath(tail)
            ctx.fillPath()
        }
        if outline {
            let ring = r + CounterGeometry.outlinePadding * scale
            let ringRect = CGRect(x: center.x - ring, y: center.y - ring, width: ring * 2, height: ring * 2)
            ctx.setFillColor(color.antiContrasting.cgColor)
            ctx.fillEllipse(in: ringRect)
            ctx.setStrokeColor(color.contrasting.cgColor)
            ctx.setLineWidth(max(scale, 1))
            ctx.strokeEllipse(in: ringRect)
        }
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        // Digits: bold, shrunk until they fit an r × r box.
        TextLayout.drawCentered("\(number)", center: center, maxWidth: r, fontSize: r, bold: true,
                                color: color.contrasting, in: ctx)
    }

    // MARK: Pixel effects

    private func drawEffect(_ a: Annotation, in ctx: CGContext) {
        let rect = a.spanRect.integral.intersection(imageBounds)
        guard !rect.isNull, rect.width >= 1, rect.height >= 1 else { return }
        let key = EffectKey(a: a, rect: rect)
        guard let image = effectImage(for: key, annotation: a, rect: rect) else { return }
        let isBlur = a.kind == .pixelate && !a.securePixelate && a.size <= 1
        ctx.drawUpright(image, in: rect, interpolation: isBlur ? .default : .none)
    }

    private func effectImage(for key: EffectKey, annotation a: Annotation, rect: CGRect) -> CGImage? {
        lock.lock()
        if let hit = effectCache[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        let image: CGImage?
        switch a.kind {
        case .invert:
            image = pixels.flatMap { Redaction.invert($0, rect: rect) }
        case .pixelate where a.securePixelate:
            image = pixels.flatMap { Redaction.securePixelate($0, rect: rect, thickness: a.size, scale: a.scale) }
        default:
            image = Redaction.classicPixelate(baseImage, rect: rect, thickness: a.size, scale: a.scale)
        }

        lock.lock()
        if effectCache.count > 96 { effectCache.removeAll(keepingCapacity: true) }
        effectCache[key] = image
        lock.unlock()
        return image
    }

    private var pixels: PixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        if cachedPixels == nil { cachedPixels = PixelBuffer(image: baseImage) }
        return cachedPixels
    }

    private struct EffectKey: Hashable {
        var kind: ToolKind
        var x: Int, y: Int, w: Int, h: Int
        var size: CGFloat
        var scale: CGFloat
        var secure: Bool

        init(a: Annotation, rect: CGRect) {
            kind = a.kind
            x = Int(rect.minX); y = Int(rect.minY); w = Int(rect.width); h = Int(rect.height)
            size = a.size
            scale = a.scale
            secure = a.securePixelate
        }
    }

    // MARK: Chrome

    /// Flameshot's object-selection outline: black 3 px under a white dotted
    /// 1 px line. `pixel` is the size of one screen pixel in image units.
    public func drawSelectionOutline(_ rect: CGRect, pixel: CGFloat, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setStrokeColor(RGBAColor.black.cgColor)
        ctx.setLineWidth(3 * pixel)
        ctx.stroke(rect)
        ctx.setStrokeColor(RGBAColor.white.cgColor)
        ctx.setLineWidth(pixel)
        ctx.setLineDash(phase: 0, lengths: [3 * pixel, 3 * pixel])
        ctx.stroke(rect)
        ctx.restoreGState()
    }

    /// The hover preview Flameshot shows under the mouse before drawing (here:
    /// Pencil hover or trackpad pointer).
    public func drawHoverPreview(settings: ToolSettings, scale: CGFloat, nextNumber: Int, at p: CGPoint, in ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        let color = settings.color
        switch settings.tool {
        case .counter:
            ctx.setAlpha(0.5)
            drawCounter(center: p, tip: p, number: nextNumber, color: color,
                        radius: CounterGeometry.radius(thickness: settings.thickness, scale: scale),
                        scale: scale, outline: settings.counterOutline, in: ctx)
        case .pencil, .line, .arrow, .rectangleOutline, .rectangleFilled, .ellipse, .marker:
            var d = max(settings.thickness * scale, 2 * scale)
            ctx.setFillColor(color.cgColor)
            if settings.tool == .marker {
                d = MarkerGeometry.width(thickness: settings.thickness, scale: scale)
                ctx.setAlpha(0.35)
            }
            ctx.fillEllipse(in: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d))
        case .text:
            let h = settings.fontSize * scale
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(max(scale, 1))
            ctx.strokeLineSegments(between: [CGPoint(x: p.x, y: p.y), CGPoint(x: p.x, y: p.y + h * 1.2)])
        case .pixelate, .invert, .move:
            break
        }
    }
}

// MARK: - Text

public enum TextLayout {
    /// Padding around text boxes, logical points (Flameshot: 5).
    public static let padding: CGFloat = 5

    static func font(size: CGFloat, bold: Bool = false) -> CTFont {
        let base = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)
        return base ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    static func lines(_ text: String, font: CTFont, color: RGBAColor) -> [CTLine] {
        text.components(separatedBy: "\n").map { line in
            let attrs: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
            ]
            return CTLineCreateWithAttributedString(NSAttributedString(string: line, attributes: attrs))
        }
    }

    static func lineHeight(_ font: CTFont) -> CGFloat {
        CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
    }

    /// Size of the padded text box for `text` at `fontSize` pixels.
    public static func boxSize(for text: String, fontSize: CGFloat, padding: CGFloat) -> CGSize {
        let f = font(size: fontSize)
        let ls = lines(text, font: f, color: .black)
        let width = ls.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) }.max() ?? 0
        return CGSize(width: ceil(width) + padding * 2, height: ceil(lineHeight(f) * CGFloat(max(ls.count, 1))) + padding * 2)
    }

    /// Draw multi-line text with its padded box's top-left at `origin`.
    public static func draw(_ text: String, at origin: CGPoint, fontSize: CGFloat, padding: CGFloat,
                            color: RGBAColor, in ctx: CGContext) {
        let f = font(size: fontSize)
        let lh = lineHeight(f)
        let ascent = CTFontGetAscent(f)
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1) // y-down context
        for (i, line) in lines(text, font: f, color: color).enumerated() {
            ctx.textPosition = CGPoint(x: origin.x + padding, y: origin.y + padding + ascent + CGFloat(i) * lh)
            CTLineDraw(line, ctx)
        }
        ctx.restoreGState()
    }

    /// Single line centred on `center`, shrinking the font until it is no wider
    /// than `maxWidth`.
    static func drawCentered(_ text: String, center: CGPoint, maxWidth: CGFloat, fontSize: CGFloat,
                             bold: Bool, color: RGBAColor, in ctx: CGContext) {
        var size = fontSize
        var f = font(size: size, bold: bold)
        var line = lines(text, font: f, color: color)[0]
        var width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        while width > maxWidth, size > 1 {
            size -= 1
            f = font(size: size, bold: bold)
            line = lines(text, font: f, color: color)[0]
            width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        }
        // Centre the cap height, not the full line box, so digits look centred.
        let capHeight = CTFontGetCapHeight(f)
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: center.x - width / 2, y: center.y + capHeight / 2)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
