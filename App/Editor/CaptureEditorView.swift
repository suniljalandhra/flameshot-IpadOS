import EmberKit
import SwiftUI
import UIKit

/// The frozen-screen editor: Flameshot's select → annotate → export workflow.
///
/// Layer order (bottom → top): screenshot, annotations, dim + selection,
/// touch input, text box, toolbar, colour wheel, toast.
struct CaptureEditorView: View {
    @Bindable var document: EditorDocument
    var onClose: () -> Void

    @State private var hover: CGPoint? // image coordinates
    @State private var picker: PickerSession?
    @State private var showPanel = false
    @State private var toast: String?
    @State private var fileToExport: PNGFile?
    @State private var showFileExporter = false

    /// Finger-sized hit radius, in view points.
    private static let touchRadius: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            let mapping = ViewportMapping(imageSize: document.imageSize, viewSize: geo.size)
            let frame = mapping.imageFrame

            ZStack(alignment: .topLeading) {
                Color.black

                Image(decorative: document.baseImage, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)

                AnnotationCanvas(document: document, mapping: mapping, hover: hover)
                SelectionOverlay(document: document, mapping: mapping)

                CanvasInput { handle($0, mapping: mapping) }

                TextEntryOverlay(document: document, mapping: mapping)

                if document.selection == nil {
                    hint.frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Like Flameshot, the buttons step aside while you drag.
                if let selection = document.selection, document.interaction == .idle, picker == nil {
                    FloatingToolbar(
                        items: toolbarItems(mapping: mapping),
                        selection: mapping.toView(selection),
                        bounds: CGRect(origin: .zero, size: geo.size).insetBy(dx: 12, dy: 16)
                    )
                    deleteButton(mapping: mapping)
                }

                if let picker {
                    RadialColorPicker(
                        session: picker,
                        current: document.settings.color,
                        onSelect: { choose(colorSlot: $0) },
                        onDismiss: { self.picker = nil }
                    )
                }

                if let toast {
                    Text(toast)
                        .font(.headline)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 24)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .background(HiddenShortcuts(document: document, isEditingText: document.pendingText != nil, actions: shortcutActions))
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .inspector(isPresented: $showPanel) {
            SidePanel(document: document,
                      onCopy: copy,
                      onSaveToPhotos: saveToPhotos,
                      onSaveToFiles: saveToFiles)
                .inspectorColumnWidth(min: 300, ideal: 340, max: 420)
        }
        .fileExporter(isPresented: $showFileExporter, document: fileToExport, contentType: .png,
                      defaultFilename: ExportService.defaultFilename()) { result in
            if case .success = result { show("Saved to Files") }
            fileToExport = nil
        }
        .animation(.easeOut(duration: 0.2), value: toast)
        .task(id: toast) {
            guard toast != nil else { return }
            try? await Task.sleep(for: .seconds(1.6))
            toast = nil
        }
    }

    private var hint: some View {
        Text("Drag to select an area, or tap to use the whole image")
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(Color.emberPurple.opacity(0.9), in: Capsule())
            .allowsHitTesting(false)
    }

    // MARK: Input

    private func handle(_ event: CanvasEvent, mapping: ViewportMapping) {
        let tolerance = Self.touchRadius / max(mapping.scale, 0.0001)
        switch event {
        case let .began(p, modifiers, role):
            picker = nil
            document.pointerDown(at: mapping.toImage(p), modifiers: modifiers, role: role, tolerance: tolerance)
        case let .moved(points, modifiers):
            document.pointerMoved(to: points.map { mapping.toImage($0) }, modifiers: modifiers)
        case let .ended(modifiers):
            document.pointerUp(modifiers: modifiers)
        case .cancelled:
            document.pointerCancelled()
        case let .hover(p):
            hover = p.map { mapping.toImage($0) }
        case let .pickerBegan(p):
            document.pointerCancelled()
            if document.pendingText?.string.isEmpty == true { document.cancelPendingText() }
            openPicker(at: p, in: mapping.viewSize, tapMode: false)
        case let .pickerMoved(p):
            guard let session = picker else { return }
            picker?.highlighted = RadialLayout.index(at: p, count: RadialColorPicker.slotCount,
                                                     around: session.center, radius: RadialColorPicker.radius)
        case .pickerEnded:
            if let index = picker?.highlighted { choose(colorSlot: index) } else { picker = nil }
        case .pencilTap:
            switch UIPencilInteraction.preferredTapAction {
            case .ignore:
                break
            case .showColorPalette:
                openPicker(at: hover.map { mapping.toView($0) } ?? mapping.imageFrame.center, in: mapping.viewSize, tapMode: true)
            default:
                document.settings.swapToPreviousTool()
            }
        case let .pencilSqueeze(p):
            let at = p ?? hover.map { mapping.toView($0) } ?? mapping.imageFrame.center
            openPicker(at: at, in: mapping.viewSize, tapMode: true)
        }
    }

    private func openPicker(at point: CGPoint, in size: CGSize, tapMode: Bool) {
        // Keep the whole wheel on screen.
        let margin = RadialColorPicker.radius + RadialColorPicker.swatchSize
        let x = min(max(point.x, margin), max(size.width - margin, margin))
        let y = min(max(point.y, margin), max(size.height - margin, margin))
        picker = PickerSession(center: CGPoint(x: x, y: y), highlighted: nil, tapMode: tapMode)
    }

    private func choose(colorSlot index: Int) {
        if index < RadialColorPicker.palette.count {
            document.settings.color = RadialColorPicker.palette[index]
        } else {
            showPanel = true // custom colour lives in the side panel
        }
        picker = nil
    }

    // MARK: Toolbar

    private func toolbarItems(mapping: ViewportMapping) -> [ToolbarButtonModel] {
        let settings = document.settings
        let keysEnabled = document.pendingText == nil
        func key(_ k: KeyEquivalent, _ m: EventModifiers = []) -> KeyboardShortcut? {
            keysEnabled ? KeyboardShortcut(k, modifiers: m) : nil
        }

        var items: [ToolbarButtonModel] = ToolKind.allCases.map { tool in
            ToolbarButtonModel(
                id: tool.rawValue, title: tool.title, systemImage: tool.systemImage,
                isActive: settings.tool == tool,
                shortcut: tool.shortcutKey.flatMap { key(KeyEquivalent($0)) },
                kind: .action { document.selectTool(tool) }
            )
        }
        let selectionCenter = document.selection.map { mapping.toView($0).center } ?? mapping.imageFrame.center
        items += [
            ToolbarButtonModel(id: "undo", title: "Undo", systemImage: "arrow.uturn.backward",
                               isEnabled: document.canUndo, shortcut: key("z", .command),
                               kind: .action { document.undo() }),
            ToolbarButtonModel(id: "redo", title: "Redo", systemImage: "arrow.uturn.forward",
                               isEnabled: document.canRedo, shortcut: key("z", [.command, .shift]),
                               kind: .action { document.redo() }),
            ToolbarButtonModel(id: "color", title: "Colour", systemImage: "paintpalette",
                               swatch: settings.color, shortcut: key("g"),
                               kind: .action { openPicker(at: selectionCenter, in: mapping.viewSize, tapMode: true) }),
            ToolbarButtonModel(id: "panel", title: "Options", systemImage: "slider.horizontal.3",
                               isActive: showPanel, shortcut: key(.space),
                               kind: .action { showPanel.toggle() }),
            ToolbarButtonModel(id: "copy", title: "Copy", systemImage: "doc.on.doc",
                               shortcut: key("c", .command), kind: .action(copy)),
            ToolbarButtonModel(id: "save", title: "Save to Photos", systemImage: "square.and.arrow.down",
                               shortcut: key("s", .command), kind: .action(saveToPhotos)),
            ToolbarButtonModel(id: "share", title: "Share", systemImage: "square.and.arrow.up",
                               kind: .share(RenderedCapture { [document] in ExportService.pngData(of: document) })),
            ToolbarButtonModel(id: "done", title: "Copy and Close", systemImage: "checkmark",
                               kind: .action(accept)),
            ToolbarButtonModel(id: "close", title: "Close", systemImage: "xmark",
                               kind: .action(onClose)),
        ]
        return items
    }

    /// Trash button next to the selected annotation (Move tool).
    @ViewBuilder
    private func deleteButton(mapping: ViewportMapping) -> some View {
        if let selected = document.selectedAnnotation {
            let box = mapping.toView(selected.boundingRect)
            Button(role: .destructive) {
                document.deleteSelectedAnnotation()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.red, in: Circle())
            }
            .buttonStyle(.plain)
            .position(x: box.maxX + 18, y: box.minY - 18)
            .accessibilityLabel("Delete annotation")
        }
    }

    // MARK: Actions

    private var shortcutActions: HiddenShortcuts.Actions {
        HiddenShortcuts.Actions(
            accept: accept,
            close: onClose,
            cancelText: { document.cancelPendingText() },
            togglePanel: { showPanel.toggle() }
        )
    }

    private func copy() {
        show(ExportService.copy(document) ? "Copied" : "Nothing to copy")
    }

    /// Flameshot's Enter: copy the capture and close.
    private func accept() {
        if document.selection != nil, ExportService.copy(document) {
            onClose()
        } else {
            show("Select an area first")
        }
    }

    private func saveToPhotos() {
        Task {
            do {
                try await ExportService.saveToPhotos(document)
                show("Saved to Photos")
            } catch {
                show(error.localizedDescription)
            }
        }
    }

    private func saveToFiles() {
        guard let data = ExportService.pngData(of: document) else { return }
        fileToExport = PNGFile(data: data)
        showFileExporter = true
    }

    private func show(_ message: String) {
        toast = message
    }
}

/// Keyboard shortcuts that work whether or not the toolbar is visible.
/// SwiftUI only registers shortcuts on views in the hierarchy, so these are
/// invisible buttons.
private struct HiddenShortcuts: View {
    struct Actions {
        var accept: () -> Void
        var close: () -> Void
        var cancelText: () -> Void
        var togglePanel: () -> Void
    }

    let document: EditorDocument
    let isEditingText: Bool
    let actions: Actions

    var body: some View {
        ZStack {
            if isEditingText {
                Button("Cancel Text", action: actions.cancelText).keyboardShortcut(.cancelAction)
            } else {
                Button("Copy and Close", action: actions.accept).keyboardShortcut(.defaultAction)
                Button("Close", action: actions.close).keyboardShortcut(.cancelAction)
                Button("Select All") { document.selectAll() }.keyboardShortcut("a", modifiers: .command)
                Button("Smaller") { document.settings.stepSize(by: -1) }.keyboardShortcut("[", modifiers: [])
                Button("Bigger") { document.settings.stepSize(by: 1) }.keyboardShortcut("]", modifiers: [])
                Button("Delete") { document.deleteSelectedAnnotation() }.keyboardShortcut(.delete, modifiers: [])
                Button("Left") { document.nudgeSelection(dx: -1, dy: 0) }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("Right") { document.nudgeSelection(dx: 1, dy: 0) }.keyboardShortcut(.rightArrow, modifiers: [])
                Button("Up") { document.nudgeSelection(dx: 0, dy: -1) }.keyboardShortcut(.upArrow, modifiers: [])
                Button("Down") { document.nudgeSelection(dx: 0, dy: 1) }.keyboardShortcut(.downArrow, modifiers: [])
                if document.selection == nil {
                    Button("Options", action: actions.togglePanel).keyboardShortcut(.space, modifiers: [])
                }
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}
