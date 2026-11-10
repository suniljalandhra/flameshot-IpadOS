import EmberKit
import SwiftUI

/// Annotations, the in-progress shape, the selected-object outline and the
/// hover preview — all drawn by EmberKit's `AnnotationRenderer`, the same code
/// that renders the export.
struct AnnotationCanvas: View {
    let document: EditorDocument
    let mapping: ViewportMapping
    /// Image coordinates.
    let hover: CGPoint?

    var body: some View {
        // Read observable state here (not inside the Canvas closure) so SwiftUI
        // tracks it and redraws on change.
        let renderer = document.renderer
        let annotations = document.annotations
        let draft = document.draft
        let selected = document.selectedAnnotation
        let settings = document.settings
        let nextNumber = document.nextCounterNumber
        let pixelScale = document.pixelScale
        let showHover = hover != nil
            && document.interaction == .idle
            && document.pendingText == nil
            && document.selection != nil
        let transform = mapping.transform
        let onePixel = 1 / max(mapping.scale, 0.0001)

        Canvas { context, _ in
            context.withCGContext { cg in
                cg.concatenate(transform)
                renderer.draw(annotations, in: cg)
                if let draft { renderer.draw(draft, in: cg) }
                if let selected {
                    renderer.drawSelectionOutline(selected.boundingRect, pixel: onePixel, in: cg)
                }
                if showHover, let hover {
                    renderer.drawHoverPreview(settings: settings, scale: pixelScale, nextNumber: nextNumber, at: hover, in: cg)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Dims everything outside the capture selection (black at 190/255, as in
/// Flameshot) and draws the selection border, handles and size label.
struct SelectionOverlay: View {
    let document: EditorDocument
    let mapping: ViewportMapping

    static let dimOpacity = 190.0 / 255.0
    static let handleDiameter: CGFloat = 14

    var body: some View {
        let selectionInImage = document.selection
        let selection = selectionInImage.map { mapping.toView($0) }

        Canvas { context, size in
            var dim = Path(CGRect(origin: .zero, size: size))
            if let selection { dim.addRect(selection) }
            context.fill(dim, with: .color(.black.opacity(Self.dimOpacity)), style: FillStyle(eoFill: true))

            guard let selection, selection.width > 0 || selection.height > 0 else { return }
            context.stroke(Path(selection), with: .color(.emberPurple), lineWidth: 1.5)
            let d = Self.handleDiameter
            for handle in SelectionHandle.allCases {
                let p = handle.position(in: selection)
                let dot = Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d))
                context.fill(dot, with: .color(.emberPurple))
                context.stroke(dot, with: .color(.white), lineWidth: 1.5)
            }
        }
        .overlay(alignment: .topLeading) {
            if let selection, let selectionInImage, selectionInImage.width >= 1 {
                Text(verbatim: "\(Int(selectionInImage.width)) × \(Int(selectionInImage.height))")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.emberPurple, in: Capsule())
                    .offset(x: selection.minX, y: max(selection.minY - 26, 4))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Inline text box for the Text tool, sized to match the rendered result.
struct TextEntryOverlay: View {
    @Bindable var document: EditorDocument
    let mapping: ViewportMapping
    @FocusState private var focused: Bool

    var body: some View {
        if let draft = document.pendingText {
            let origin = mapping.toView(draft.origin)
            let pointsPerUnit = document.pixelScale * mapping.scale
            TextField("Type here", text: Binding(
                get: { document.pendingText?.string ?? "" },
                set: { document.pendingText?.string = $0 }
            ))
            .font(.system(size: document.settings.fontSize * pointsPerUnit))
            .foregroundStyle(Color(document.settings.color))
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .frame(minWidth: 60, alignment: .leading)
            .fixedSize()
            .padding(TextLayout.padding * pointsPerUnit)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color.emberPurple, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .offset(x: origin.x, y: origin.y)
            .focused($focused)
            .onAppear { focused = true }
            .onSubmit { document.commitPendingText() }
        }
    }
}
