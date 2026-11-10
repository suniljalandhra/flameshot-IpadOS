import CoreGraphics
import CoreImage
import Foundation

/// Pixel effects that read the original screenshot.
public enum Redaction {
    /// Number of blocks across a pixelated area. Flameshot:
    /// `size · 0.5 / (thickness + 1)`, measured in logical points.
    public static func blockCount(length: CGFloat, thickness: CGFloat, scale: CGFloat) -> Int {
        max(Int(length / max(scale, 1) * 0.5 / max(thickness + 1, 1)), 1)
    }

    // MARK: Secure pixelate (default)

    /// Irreversible pixelation. **The pixels inside `rect` are never read.**
    /// Each block is synthesised from the 1-pixel strips just outside the four
    /// edges (sampled with Gaussian jitter and blended by position) plus a
    /// little noise, so the result looks like a smear of the surroundings and
    /// leaks nothing about what it covers.
    ///
    /// - Returns: a small image, one pixel per block; draw it over `rect` with
    ///   `.none` interpolation.
    public static func securePixelate(_ source: PixelBuffer, rect: CGRect, thickness: CGFloat, scale: CGFloat) -> CGImage? {
        let sel = rect.integral.intersection(source.bounds)
        guard !sel.isNull, sel.width >= 1, sel.height >= 1 else { return nil }
        let x0 = Int(sel.minX), y0 = Int(sel.minY), x1 = Int(sel.maxX) - 1, y1 = Int(sel.maxY) - 1

        // Fringe strips: one row/column outside each edge (or the edge itself
        // when the rect touches the image border).
        let topY = y0 > 0 ? y0 - 1 : y0
        let bottomY = y1 < source.height - 1 ? y1 + 1 : y1
        let leftX = x0 > 0 ? x0 - 1 : x0
        let rightX = x1 < source.width - 1 ? x1 + 1 : x1

        let bw = blockCount(length: sel.width, thickness: thickness, scale: scale)
        let bh = blockCount(length: sel.height, thickness: thickness, scale: scale)
        var out = PixelBuffer(width: bw, height: bh)
        var rng = SeededGenerator(seed: 42)
        let sigma = Double(5 * thickness + 1) * Double(max(scale, 1))
        let spanX = x1 - x0, spanY = y1 - y0

        func sample(x: Int, y: Int) -> SIMD3<Double> {
            let p = source.pixel(x: x, y: y)
            return SIMD3(Double(p.r), Double(p.g), Double(p.b)) / 255
        }

        for by in 0..<bh {
            for bx in 0..<bw {
                let h = Double(bx) / Double(bw)
                let v = Double(by) / Double(bh)
                func jitterX() -> Int { (x0 + Int(h * Double(spanX) + rng.gaussian(sigma: sigma))).clamped(to: x0...x1) }
                func jitterY() -> Int { (y0 + Int(v * Double(spanY) + rng.gaussian(sigma: sigma))).clamped(to: y0...y1) }
                let top = sample(x: jitterX(), y: topY)
                let bottom = sample(x: jitterX(), y: bottomY)
                let left = sample(x: leftX, y: jitterY())
                let right = sample(x: rightX, y: jitterY())
                let horizontal = left * (1 - h) + right * h
                let vertical = top * (1 - v) + bottom * v
                let noise = rng.gaussian(sigma: 0.1)
                let c = (horizontal * 0.5 + vertical * 0.5) + SIMD3(repeating: noise)
                func byte(_ d: Double) -> UInt8 { UInt8((d * 255).rounded().clamped(to: 0...255)) }
                out.setPixel(x: bx, y: by, (byte(c.x), byte(c.y), byte(c.z), 255))
            }
        }
        return out.makeImage()
    }

    // MARK: Classic pixelate / blur (opt-in, reversible-ish)

    /// Flameshot's "insecure" mode: thickness <= 1 blurs, otherwise the area is
    /// averaged down to blocks. Returns an image to draw over `rect`
    /// (blocks: `.none` interpolation; blur: full size).
    public static func classicPixelate(_ base: CGImage, rect: CGRect, thickness: CGFloat, scale: CGFloat) -> CGImage? {
        let sel = rect.integral.intersection(CGRect(x: 0, y: 0, width: base.width, height: base.height))
        guard !sel.isNull, sel.width >= 1, sel.height >= 1, let crop = base.cropping(to: sel) else { return nil }

        if thickness <= 1 {
            let input = CIImage(cgImage: crop)
            let blurred = input.clampedToExtent()
                .applyingGaussianBlur(sigma: 10 * Double(scale))
                .applyingGaussianBlur(sigma: 12 * Double(scale))
                .cropped(to: input.extent)
            return sharedCIContext.createCGImage(blurred, from: input.extent)
        }

        let bw = blockCount(length: sel.width, thickness: thickness, scale: scale)
        let bh = blockCount(length: sel.height, thickness: thickness, scale: scale)
        guard let ctx = CGContext(
            data: nil, width: bw, height: bh, bitsPerComponent: 8, bytesPerRow: 0,
            space: PixelBuffer.colorSpace, bitmapInfo: PixelBuffer.bitmapInfo
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: bw, height: bh))
        return ctx.makeImage()
    }

    // MARK: Invert

    public static func invert(_ source: PixelBuffer, rect: CGRect) -> CGImage? {
        guard var crop = source.cropped(to: rect) else { return nil }
        for y in 0..<crop.height {
            for x in 0..<crop.width {
                let p = crop.pixel(x: x, y: y)
                // Premultiplied: inverting a colour channel is alpha - c.
                crop.setPixel(x: x, y: y, (p.a &- p.r, p.a &- p.g, p.a &- p.b, p.a))
            }
        }
        return crop.makeImage()
    }

    static let sharedCIContext = CIContext(options: [.cacheIntermediates: false])
}

/// Deterministic PRNG (SplitMix64) so a pixelated area renders identically
/// every frame and on export, like Flameshot's fixed seed.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Box–Muller normal sample with mean 0.
    mutating func gaussian(sigma: Double) -> Double {
        let u1 = max(Double.random(in: 0..<1, using: &self), .leastNonzeroMagnitude)
        let u2 = Double.random(in: 0..<1, using: &self)
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2) * sigma
    }
}
