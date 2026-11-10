import CoreGraphics
import Foundation
import Observation

/// Whether a pointer should draw, or only select / move things. With "Pencil
/// only draws" enabled, finger touches arrive as `.navigate`.
public enum PointerRole: Sendable {
    case draw
    case navigate
}

public struct InputModifiers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    /// Hardware-keyboard Shift: snap angles / squares.
    public static let shift = InputModifiers(rawValue: 1 << 0)
}

/// A text box being typed into. It becomes an annotation on commit.
public struct TextDraft: Equatable, Sendable {
    public var origin: CGPoint
    public var string: String
}

/// The whole editor state for one capture: the frozen screenshot, the capture
/// selection, annotations, tool settings and undo history. Views send pointer
/// events in **image coordinates**; everything else is derived from here.
@MainActor
@Observable
public final class EditorDocument {
    public enum Interaction: Equatable {
        case idle
        case creatingSelection(origin: CGPoint)
        case resizingSelection(handle: SelectionHandle, original: CGRect, start: CGPoint)
        case movingSelection(original: CGRect, start: CGPoint)
        case drawing
        case movingAnnotation(id: UUID, original: Annotation, start: CGPoint)
    }

    public static let undoLimit = 100

    @ObservationIgnored public let renderer: AnnotationRenderer
    /// Image pixels per point of the capture (2 for every current iPad).
    public let pixelScale: CGFloat
    public let imageSize: CGSize
    public var imageBounds: CGRect { CGRect(origin: .zero, size: imageSize) }

    /// The capture area, or `nil` before the first drag.
    public var selection: CGRect?
    public private(set) var annotations: [Annotation] = []
    /// The shape being drawn right now.
    public private(set) var draft: Annotation?
    public var selectedAnnotationID: UUID?
    public var settings: ToolSettings
    public var pendingText: TextDraft?
    public private(set) var interaction: Interaction = .idle

    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []
    @ObservationIgnored private var snapshotBeforeMove: [Annotation]?

    public init(image: CGImage, pixelScale: CGFloat = 2, settings: ToolSettings = ToolSettings()) {
        renderer = AnnotationRenderer(baseImage: image)
        self.pixelScale = max(pixelScale, 1)
        imageSize = CGSize(width: image.width, height: image.height)
        self.settings = settings
    }

    public var baseImage: CGImage { renderer.baseImage }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var hasSelection: Bool { selection != nil }

    public var selectedAnnotation: Annotation? {
        guard let id = selectedAnnotationID else { return nil }
        return annotations.first { $0.id == id }
    }

    /// Next number for the counter tool. Unlike Flameshot, undoing a counter
    /// frees its number.
    public var nextCounterNumber: Int {
        let highest = annotations.lazy.filter { $0.kind == .counter }.map(\.number).max() ?? 0
        return min(highest + 1, 999)
    }

    // MARK: Pointer input

    /// - Parameter tolerance: hit-test radius in image pixels (convert a
    ///   finger-sized radius from view points before calling).
    public func pointerDown(at point: CGPoint, modifiers: InputModifiers = [], role: PointerRole = .draw, tolerance: CGFloat = 20) {
        let p = clampToImage(point)

        if pendingText != nil {
            // Tapping away from a text box commits it, like Flameshot.
            commitPendingText()
            interaction = .idle
            return
        }

        guard let sel = selection else {
            beginSelection(at: p)
            return
        }

        if let handle = SelectionHandle.hit(p, in: sel, tolerance: tolerance) {
            interaction = .resizingSelection(handle: handle, original: sel, start: p)
            return
        }

        if role == .navigate || settings.tool == .move {
            if let hit = annotations.last(where: { $0.contains(p, tolerance: tolerance / 2) }) {
                selectedAnnotationID = hit.id
                snapshotBeforeMove = annotations
                interaction = .movingAnnotation(id: hit.id, original: hit, start: p)
            } else if sel.contains(p) {
                selectedAnnotationID = nil
                interaction = .movingSelection(original: sel, start: p)
            } else {
                selectedAnnotationID = nil
                beginSelection(at: p)
            }
            return
        }

        selectedAnnotationID = nil
        if settings.tool == .text {
            pendingText = TextDraft(origin: p, string: "")
            interaction = .idle
            return
        }
        draft = newAnnotation(at: p)
        interaction = .drawing
    }

    /// Pass every coalesced sample, oldest first, for smooth Pencil strokes.
    public func pointerMoved(to points: [CGPoint], modifiers: InputModifiers = []) {
        guard let raw = points.last else { return }
        let last = clampToImage(raw)

        switch interaction {
        case .idle:
            break
        case .creatingSelection(let origin):
            selection = CGRect(corner: origin, opposite: last)
        case let .resizingSelection(handle, original, start):
            selection = handle.resize(original, by: last - start, within: imageBounds)
        case let .movingSelection(original, start):
            selection = original.moved(by: last - start, within: imageBounds)
        case let .movingAnnotation(id, original, start):
            if let i = annotations.firstIndex(where: { $0.id == id }) {
                annotations[i] = original.translated(by: last - start)
            }
        case .drawing:
            guard var d = draft else { return }
            if d.kind == .pencil {
                for p in points.map(clampToImage) where p.distance(to: d.points[d.points.count - 1]) >= 0.5 {
                    d.points.append(p)
                }
            } else {
                let snap = modifiers.contains(.shift) || settings.alwaysSnap
                let v = last - d.first
                d.points = [d.first, d.first + (snap ? Snapping.adjust(v, mode: d.kind.snapMode) : v)]
            }
            draft = d
        }
    }

    public func pointerMoved(to point: CGPoint, modifiers: InputModifiers = []) {
        pointerMoved(to: [point], modifiers: modifiers)
    }

    public func pointerUp(modifiers: InputModifiers = []) {
        switch interaction {
        case .creatingSelection:
            // A tap (no real drag) selects the whole capture.
            if let s = selection, s.width < 4 || s.height < 4 {
                selection = imageBounds
            }
        case .drawing:
            if let d = draft, d.isValid { commit(d) }
            draft = nil
        case .movingAnnotation:
            if let before = snapshotBeforeMove, before != annotations { pushUndo(before) }
            snapshotBeforeMove = nil
        default:
            break
        }
        interaction = .idle
    }

    public func pointerCancelled() {
        if case .movingAnnotation = interaction, let before = snapshotBeforeMove {
            annotations = before
        }
        snapshotBeforeMove = nil
        draft = nil
        interaction = .idle
    }

    // MARK: Text

    public func commitPendingText() {
        guard let t = pendingText else { return }
        pendingText = nil
        let a = Annotation(kind: .text, points: [t.origin], color: settings.color,
                           size: settings.fontSize, scale: pixelScale, text: t.string)
        if a.isValid { commit(a) }
    }

    public func cancelPendingText() {
        pendingText = nil
    }

    // MARK: Editing

    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
        selectedAnnotationID = nil
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        selectedAnnotationID = nil
    }

    public func deleteSelectedAnnotation() {
        guard let id = selectedAnnotationID, annotations.contains(where: { $0.id == id }) else { return }
        pushUndo(annotations)
        annotations.removeAll { $0.id == id }
        selectedAnnotationID = nil
    }

    public func clearAnnotations() {
        guard !annotations.isEmpty else { return }
        pushUndo(annotations)
        annotations.removeAll()
        selectedAnnotationID = nil
    }

    public func selectAll() {
        selection = imageBounds
    }

    /// Arrow keys move the selection by one point.
    public func nudgeSelection(dx: CGFloat, dy: CGFloat) {
        guard let s = selection else { return }
        selection = s.moved(by: CGVector(dx: dx * pixelScale, dy: dy * pixelScale), within: imageBounds)
    }

    public func selectTool(_ tool: ToolKind) {
        if pendingText != nil { commitPendingText() }
        settings.select(tool)
        if tool != .move { selectedAnnotationID = nil }
    }

    // MARK: Export

    /// Screenshot + annotations, cropped to the selection.
    public func flattenedImage() -> CGImage? {
        if pendingText != nil { commitPendingText() }
        return Flattener.render(renderer: renderer, annotations: annotations, crop: selection)
    }

    // MARK: Private

    private func beginSelection(at p: CGPoint) {
        selection = CGRect(origin: p, size: .zero)
        interaction = .creatingSelection(origin: p)
    }

    private func newAnnotation(at p: CGPoint) -> Annotation {
        let s = settings
        return Annotation(
            kind: s.tool,
            points: s.tool == .pencil ? [p] : [p, p],
            color: s.color,
            size: s.tool.usesFontSize ? s.fontSize : s.thickness,
            scale: pixelScale,
            number: s.tool == .counter ? nextCounterNumber : 0,
            arrowStyle: s.arrowStyle,
            counterOutline: s.counterOutline,
            securePixelate: s.securePixelate
        )
    }

    private func commit(_ a: Annotation) {
        pushUndo(annotations)
        annotations.append(a)
    }

    private func pushUndo(_ snapshot: [Annotation]) {
        undoStack.append(snapshot)
        if undoStack.count > Self.undoLimit { undoStack.removeFirst(undoStack.count - Self.undoLimit) }
        redoStack.removeAll()
    }

    private func clampToImage(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), imageSize.width), y: min(max(p.y, 0), imageSize.height))
    }
}
