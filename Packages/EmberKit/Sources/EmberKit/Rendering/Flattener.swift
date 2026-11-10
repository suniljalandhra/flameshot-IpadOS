import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Produces the exported image: screenshot + annotations, cropped to the
/// selection (Flameshot's "accept").
public enum Flattener {
    public static func render(renderer: AnnotationRenderer, annotations: [Annotation], crop: CGRect?) -> CGImage? {
        let full = renderer.imageBounds
        let area = (crop ?? full).integral.intersection(full)
        guard !area.isNull, area.width >= 1, area.height >= 1 else { return nil }
        guard let ctx = CGContext(
            data: nil, width: Int(area.width), height: Int(area.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: PixelBuffer.colorSpace, bitmapInfo: PixelBuffer.bitmapInfo
        ) else { return nil }
        // Make the context y-down in image coordinates.
        ctx.translateBy(x: 0, y: area.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -area.minX, y: -area.minY)
        ctx.drawUpright(renderer.baseImage, in: full, interpolation: .none)
        renderer.draw(annotations, in: ctx)
        return ctx.makeImage()
    }
}

public enum ImageEncoding {
    public static func png(_ image: CGImage) -> Data? {
        encode(image, type: .png, options: [:])
    }

    public static func heic(_ image: CGImage, quality: Double = 0.85) -> Data? {
        encode(image, type: .heic, options: [kCGImageDestinationLossyCompressionQuality: quality])
    }

    public static func jpeg(_ image: CGImage, quality: Double = 0.9) -> Data? {
        encode(image, type: .jpeg, options: [kCGImageDestinationLossyCompressionQuality: quality])
    }

    /// Decode the first image in `data`, applying its EXIF orientation.
    public static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 16_384,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Downscaled, orientation-corrected preview without decoding the full image.
    public static func thumbnail(at url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func encode(_ image: CGImage, type: UTType, options: [CFString: Any]) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }
}
