/// How a two-point tool's drag vector snaps when Shift (or "always snap") is on.
public enum SnapMode: Sendable {
    case none
    /// 0°, 45°, 90°, … (lines, arrows, marker)
    case octilinear
    /// Force |dx| == |dy| (squares and circles)
    case square
}

/// The annotation tools, in Flameshot's default toolbar order.
public enum ToolKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case pencil
    case line
    case arrow
    /// Flameshot calls this the "Selection" tool: an outlined rectangle.
    case rectangleOutline
    /// Flameshot's "Rectangle" tool: filled, rounded by the thickness.
    case rectangleFilled
    case ellipse
    case marker
    case text
    case pixelate
    case invert
    case counter
    /// Select / move annotations, or move the capture selection.
    case move

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pencil: "Pencil"
        case .line: "Line"
        case .arrow: "Arrow"
        case .rectangleOutline: "Rectangle"
        case .rectangleFilled: "Filled Rectangle"
        case .ellipse: "Circle"
        case .marker: "Marker"
        case .text: "Text"
        case .pixelate: "Pixelate"
        case .invert: "Invert"
        case .counter: "Counter"
        case .move: "Move"
        }
    }

    /// SF Symbol name.
    public var systemImage: String {
        switch self {
        case .pencil: "scribble"
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .rectangleOutline: "rectangle"
        case .rectangleFilled: "rectangle.fill"
        case .ellipse: "circle"
        case .marker: "highlighter"
        case .text: "textformat"
        case .pixelate: "checkerboard.rectangle"
        case .invert: "circle.lefthalf.filled"
        case .counter: "1.circle"
        case .move: "arrow.up.and.down.and.arrow.left.and.right"
        }
    }

    /// Flameshot's single-key shortcut (hardware keyboard).
    public var shortcutKey: Character? {
        switch self {
        case .pencil: "p"
        case .line: "d"
        case .arrow: "a"
        case .rectangleOutline: "s"
        case .rectangleFilled: "r"
        case .ellipse: "c"
        case .marker: "m"
        case .text: "t"
        case .pixelate: "b"
        case .invert: "i"
        case .counter: "n"
        case .move: "v"
        }
    }

    public var snapMode: SnapMode {
        switch self {
        case .line, .arrow, .marker: .octilinear
        case .rectangleOutline, .rectangleFilled, .ellipse, .pixelate, .invert: .square
        case .pencil, .text, .counter, .move: .none
        }
    }

    /// Text sizes come from the font size; everything else from the thickness.
    public var usesFontSize: Bool { self == .text }

    /// Tools that create annotations (everything except `.move`).
    public var draws: Bool { self != .move }

    /// Tools whose result is computed from the screenshot's pixels.
    public var isEffect: Bool { self == .pixelate || self == .invert }
}

public enum ArrowStyle: Int, Codable, Sendable, CaseIterable {
    case standard = 0
    case curved = 1

    public var title: String { self == .standard ? "Default" : "Curved" }
}
