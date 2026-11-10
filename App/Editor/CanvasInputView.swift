import EmberKit
import SwiftUI
import UIKit

/// Raw pointer input for the editor, in **view** coordinates.
enum CanvasEvent {
    case began(CGPoint, InputModifiers, PointerRole)
    /// Coalesced samples since the last event, oldest first.
    case moved([CGPoint], InputModifiers)
    case ended(InputModifiers)
    case cancelled
    /// Pencil hover or trackpad pointer; `nil` when it leaves.
    case hover(CGPoint?)
    /// Radial colour picker driven by the same touch (long-press / right-click).
    case pickerBegan(CGPoint)
    case pickerMoved(CGPoint)
    case pickerEnded
    /// Apple Pencil double-tap.
    case pencilTap
    /// Apple Pencil Pro squeeze, at the hover location if known.
    case pencilSqueeze(CGPoint?)
}

/// UIKit is used here (rather than SwiftUI gestures) because the editor needs
/// things SwiftUI doesn't expose: touch type (Pencil vs finger), coalesced
/// touches for smooth strokes, hardware-keyboard modifier flags, secondary
/// clicks, Pencil hover, double-tap and squeeze.
final class CanvasInputUIView: UIView, UIPencilInteractionDelegate {
    var onEvent: (CanvasEvent) -> Void = { _ in }

    private var activeTouch: UITouch?
    private var startLocation: CGPoint = .zero
    private var longPress: DispatchWorkItem?
    private var pickerActive = false
    /// Once a Pencil has been used, honour the system's "Only Draw with Apple
    /// Pencil" setting: fingers then select and move instead of drawing.
    private var sawPencil = false

    static let longPressDelay: TimeInterval = 0.45
    static let longPressSlop: CGFloat = 10

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true

        let pencil = UIPencilInteraction()
        pencil.delegate = self
        addInteraction(pencil)

        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:))))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // One pointer at a time; extra fingers are ignored.
        guard activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch
        if touch.type == .pencil { sawPencil = true }
        let p = touch.location(in: self)
        startLocation = p

        if event?.buttonMask.contains(.secondary) == true {
            // Trackpad / mouse right-click: Flameshot's right-click colour wheel.
            pickerActive = true
            onEvent(.pickerBegan(p))
            return
        }

        let pencilOnly = sawPencil && UIPencilInteraction.prefersPencilOnlyDrawing
        let role: PointerRole = (touch.type == .direct && pencilOnly) ? .navigate : .draw
        onEvent(.began(p, modifiers(event), role))
        if touch.type == .direct { scheduleLongPress() }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        let p = touch.location(in: self)
        if pickerActive {
            onEvent(.pickerMoved(p))
            return
        }
        if hypot(p.x - startLocation.x, p.y - startLocation.y) > Self.longPressSlop { cancelLongPress() }
        let samples = event?.coalescedTouches(for: touch)?.map { $0.location(in: self) } ?? [p]
        onEvent(.moved(samples.isEmpty ? [p] : samples, modifiers(event)))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        finish(cancelled: false, event: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        finish(cancelled: true, event: event)
    }

    private func finish(cancelled: Bool, event: UIEvent?) {
        cancelLongPress()
        if pickerActive {
            pickerActive = false
            onEvent(.pickerEnded)
        } else {
            onEvent(cancelled ? .cancelled : .ended(modifiers(event)))
        }
        activeTouch = nil
    }

    private func modifiers(_ event: UIEvent?) -> InputModifiers {
        event?.modifierFlags.contains(.shift) == true ? .shift : []
    }

    // MARK: Long-press → colour wheel

    private func scheduleLongPress() {
        cancelLongPress()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.activeTouch != nil, !self.pickerActive else { return }
            self.pickerActive = true
            self.onEvent(.cancelled) // drop the shape that had started
            self.onEvent(.pickerBegan(self.startLocation))
        }
        longPress = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.longPressDelay, execute: work)
    }

    private func cancelLongPress() {
        longPress?.cancel()
        longPress = nil
    }

    // MARK: Hover

    @objc private func hovered(_ recognizer: UIHoverGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            onEvent(.hover(recognizer.location(in: self)))
        default:
            onEvent(.hover(nil))
        }
    }

    // MARK: UIPencilInteractionDelegate

    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        onEvent(.pencilTap)
    }

    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        guard squeeze.phase == .ended else { return }
        onEvent(.pencilSqueeze(squeeze.hoverPose?.location))
    }
}

struct CanvasInput: UIViewRepresentable {
    var onEvent: (CanvasEvent) -> Void

    func makeUIView(context: Context) -> CanvasInputUIView {
        CanvasInputUIView(frame: .zero)
    }

    func updateUIView(_ view: CanvasInputUIView, context: Context) {
        view.onEvent = onEvent
    }
}
