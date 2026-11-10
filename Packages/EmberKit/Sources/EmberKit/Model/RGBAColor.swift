import CoreGraphics

/// An sRGB colour stored as plain values so annotations stay `Codable` and
/// `Sendable`. Components are 0...1.
public struct RGBAColor: Equatable, Hashable, Codable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `0xRRGGBB`
    public init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    public func withAlpha(_ alpha: Double) -> RGBAColor {
        RGBAColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// Perceived luma (Rec. 601 weights). Flameshot treats luma <= 0.5 as dark
    /// and picks white text / outlines on dark colours.
    public var luma: Double { 0.299 * red + 0.587 * green + 0.114 * blue }
    public var isDark: Bool { luma <= 0.5 }

    /// Colour that reads well on top of this one (counter digits).
    public var contrasting: RGBAColor { isDark ? .white : .black }
    /// Colour used for the ring around the counter bubble.
    public var antiContrasting: RGBAColor { isDark ? .black : .white }
}

public extension RGBAColor {
    static let white = RGBAColor(hex: 0xFFFFFF)
    static let black = RGBAColor(hex: 0x000000)
    static let red = RGBAColor(hex: 0xFF0000)

    /// Flameshot's UI colour, rgb(116, 0, 150).
    static let uiPurple = RGBAColor(hex: 0x740096)
    /// Flameshot's contrast UI colour, rgb(39, 0, 50).
    static let uiContrast = RGBAColor(hex: 0x270032)

    /// Flameshot's default small palette, minus the leading "custom" slot.
    /// Order matters: it is the order around the radial picker.
    static let defaultPalette: [RGBAColor] = [
        RGBAColor(hex: 0x800000), // dark red
        RGBAColor(hex: 0xFF0000), // red
        RGBAColor(hex: 0xFFFF00), // yellow
        RGBAColor(hex: 0x00FF00), // green
        RGBAColor(hex: 0x008000), // dark green
        RGBAColor(hex: 0x00FFFF), // cyan
        RGBAColor(hex: 0x0000FF), // blue
        RGBAColor(hex: 0xFF00FF), // magenta
        RGBAColor(hex: 0x800080), // dark magenta
    ]
}
