import CoreGraphics
import Foundation

/// 8-bit premultiplied RGBA pixels, row 0 at the **top** of the image.
/// Used by the pixel effects (pixelate, invert) so they can read the original
/// screenshot directly.
public struct PixelBuffer: Sendable {
    public let width: Int
    public let height: Int
    public var bytes: [UInt8]

    public static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    static let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

    public init(width: Int, height: Int, bytes: [UInt8]? = nil) {
        self.width = width
        self.height = height
        self.bytes = bytes ?? [UInt8](repeating: 0, count: width * height * 4)
    }

    public init?(image: CGImage) {
        self.init(width: image.width, height: image.height)
        let ok = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: Self.colorSpace, bitmapInfo: Self.bitmapInfo
            ) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        if !ok { return nil }
    }

    public var bounds: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }

    @inline(__always)
    public func pixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let i = (y * width + x) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
    }

    @inline(__always)
    public mutating func setPixel(x: Int, y: Int, _ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) {
        let i = (y * width + x) * 4
        bytes[i] = p.r; bytes[i + 1] = p.g; bytes[i + 2] = p.b; bytes[i + 3] = p.a
    }

    /// Copy of an integral sub-rect (clipped to the buffer).
    public func cropped(to rect: CGRect) -> PixelBuffer? {
        let r = rect.integral.intersection(bounds)
        guard !r.isNull, r.width >= 1, r.height >= 1 else { return nil }
        let x0 = Int(r.minX), y0 = Int(r.minY), w = Int(r.width), h = Int(r.height)
        var out = PixelBuffer(width: w, height: h)
        for y in 0..<h {
            let src = ((y0 + y) * width + x0) * 4
            let dst = y * w * 4
            out.bytes.replaceSubrange(dst..<(dst + w * 4), with: bytes[src..<(src + w * 4)])
        }
        return out
    }

    public func makeImage() -> CGImage? {
        var copy = bytes
        return copy.withUnsafeMutableBytes { raw -> CGImage? in
            CGContext(
                data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: Self.colorSpace, bitmapInfo: Self.bitmapInfo
            )?.makeImage()
        }
    }
}

public extension CGContext {
    /// Draw an image upright in a y-down (UIKit/SwiftUI-style) context.
    func drawUpright(_ image: CGImage, in rect: CGRect, interpolation: CGInterpolationQuality = .default) {
        saveGState()
        interpolationQuality = interpolation
        translateBy(x: 0, y: rect.minY + rect.maxY)
        scaleBy(x: 1, y: -1)
        draw(image, in: rect)
        restoreGState()
    }
}
