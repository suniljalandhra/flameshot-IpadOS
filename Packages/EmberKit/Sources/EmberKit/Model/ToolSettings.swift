import CoreGraphics

/// User-adjustable drawing state. Persisted between sessions, like Flameshot's
/// config file.
public struct ToolSettings: Equatable, Codable, Sendable {
    public var tool: ToolKind = .arrow
    public var previousTool: ToolKind = .pencil
    public var color: RGBAColor = .red
    /// Flameshot default: 3.
    public var thickness: CGFloat = 3
    /// Flameshot defaults to 8 pt on a desktop; that is too small to read on an
    /// iPad capture, so Ember starts at 18.
    public var fontSize: CGFloat = 18
    public var arrowStyle: ArrowStyle = .standard
    public var counterOutline = true
    /// Fill pixelated areas from their surroundings instead of the hidden
    /// pixels (Flameshot's default, irreversible redaction).
    public var securePixelate = true
    /// Snap without holding Shift (for people without a hardware keyboard).
    public var alwaysSnap = false

    public static let thicknessRange: ClosedRange<CGFloat> = 1...60
    public static let fontSizeRange: ClosedRange<CGFloat> = 6...200

    public init() {}

    /// Thickness or font size, whichever the current tool uses.
    public var activeSize: CGFloat {
        get { tool.usesFontSize ? fontSize : thickness }
        set {
            if tool.usesFontSize {
                fontSize = newValue.clamped(to: Self.fontSizeRange)
            } else {
                thickness = newValue.clamped(to: Self.thicknessRange)
            }
        }
    }

    public var activeSizeRange: ClosedRange<CGFloat> {
        tool.usesFontSize ? Self.fontSizeRange : Self.thicknessRange
    }

    /// Switch tool, remembering the old one (Pencil double-tap swaps back).
    public mutating func select(_ newTool: ToolKind) {
        guard newTool != tool else { return }
        previousTool = tool
        tool = newTool
    }

    public mutating func swapToPreviousTool() {
        (tool, previousTool) = (previousTool, tool)
    }

    /// Flameshot's size +/- buttons and mouse wheel step by 1.
    public mutating func stepSize(by delta: CGFloat) {
        activeSize += delta
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
