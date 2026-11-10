import EmberKit
import SwiftUI
import UIKit

extension Color {
    init(_ c: RGBAColor) {
        self.init(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
    }

    /// Flameshot's UI colour.
    static let emberPurple = Color(RGBAColor.uiPurple)
}

extension RGBAColor {
    init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        func unit(_ v: CGFloat) -> Double { Double(min(max(v, 0), 1)) }
        self.init(red: unit(r), green: unit(g), blue: unit(b), alpha: unit(a))
    }
}

extension UIImage {
    /// A CGImage for any UIImage, including CIImage-backed ones and ones with a
    /// non-up orientation.
    var normalizedCGImage: CGImage? {
        if imageOrientation == .up, let cg = cgImage { return cg }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }
}
