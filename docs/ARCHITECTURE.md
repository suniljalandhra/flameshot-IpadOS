# Ember — iPadOS architecture

Ember is a native SwiftUI iPad app that reproduces Flameshot's workflow
(freeze → select → annotate → export) as specified in [BLUEPRINT.md](BLUEPRINT.md).

## Platform reality check

Flameshot works because a desktop app can grab the whole screen on a hotkey and
cover it with a full-screen window. iPadOS allows neither. The capture side is
therefore redesigned around what the OS permits:

| Capture path | API | What it can see | Role in Ember |
| --- | --- | --- | --- |
| **Latest screenshot** | PhotoKit (`PHAsset` with `.photoScreenshot` subtype) | anything the user screenshotted with top button + volume up, or the Pencil corner swipe | primary, zero-friction path |
| **Photo picker / paste** | `PhotosPicker`, `UIPasteboard` | any image | fallback |
| **Screen broadcast** | ReplayKit *Broadcast Upload Extension* (`RPBroadcastSampleHandler`) + `RPSystemBroadcastPickerView` | the **whole device screen**, including other apps | Flameshot-style "freeze the screen": the extension keeps a ring buffer of recent frames in the App Group; the app lets you pick one |
| In-app capture | `RPScreenRecorder.startCapture` | **only Ember's own UI** | deliberately not used — it can't see other apps |

The broadcast extension runs with a ~50 MB memory cap, so it never holds frames
in memory: it throttles to 2 fps, encodes each frame as HEIC and writes it to a
fixed set of slots on disk (`BroadcastFrameStore`).

## Module layout

```
flameshot-ipad/
├── project.yml                     XcodeGen spec → Ember.xcodeproj
├── Packages/EmberKit/              platform-neutral core (builds + tests on macOS)
│   ├── Sources/EmberKit/
│   │   ├── Model/                  RGBAColor, ToolKind, Annotation, ToolSettings
│   │   ├── Geometry/
│   │   │   ├── ShapeGeometry       Snapping, ArrowGeometry, CounterGeometry,
│   │   │   │                       RectangleGeometry, SelectionHandle
│   │   │   └── LayoutGeometry      ToolbarLayout (Flameshot button placement),
│   │   │                           RadialLayout (colour wheel), ViewportMapping
│   │   ├── Rendering/              AnnotationRenderer + TextLayout (CoreGraphics /
│   │   │                           CoreText), Redaction (secure & classic
│   │   │                           pixelate, invert), PixelBuffer, Flattener,
│   │   │                           ImageEncoding
│   │   ├── Document/               EditorDocument (@Observable state + undo/redo)
│   │   └── Capture/                BroadcastFrameStore (App Group ring buffer)
│   └── Tests/EmberKitTests/        Swift Testing suites (36 tests)
├── App/                            iPad app target (SwiftUI + UIKit bridges)
│   ├── EmberApp.swift              App, RootView, AppModel (settings persistence)
│   ├── Home/HomeView               capture sources
│   ├── Capture/                    PhotoLibraryService, BroadcastCapture
│   │                               (RPSystemBroadcastPickerView bridge)
│   ├── Editor/
│   │   ├── CaptureEditorView       layers, event routing, shortcuts, export actions
│   │   ├── CanvasInputView         UIKit touch / Pencil / hover / squeeze input
│   │   ├── EditorLayers            AnnotationCanvas, SelectionOverlay, TextEntryOverlay
│   │   ├── FloatingToolbar         toolbar buttons + RadialColorPicker
│   │   └── SidePanel               inspector: tools, colour, size, options, export
│   ├── Export/ExportService        copy, Photos, RenderedCapture (Transferable), PNGFile
│   └── Support/ColorSupport        Color ↔ RGBAColor, UIImage normalisation
├── BroadcastExtension/             RPBroadcastSampleHandler → BroadcastFrameStore
└── scripts/test-emberkit.sh        runs the package tests without full Xcode
```

Why a package: everything that defines *Flameshot behaviour* (geometry, rendering,
undo, layout) is pure Swift + CoreGraphics, so it is unit-tested with
`swift test` on a Mac without a simulator. The app target is a thin SwiftUI/UIKit
shell around it.

## State and data flow

```
            ┌──────────────┐  InputEvent   ┌──────────────────┐
 Pencil ───►│CanvasInputView├─────────────►│  EditorDocument  │◄── toolbar / side panel /
 touch      │ (UIKit)       │ (image coords)│  @Observable     │    keyboard shortcuts
 trackpad   └──────────────┘               │  • baseImage     │
 keyboard ⇧                                 │  • selection     │
                                            │  • annotations   │──► AnnotationCanvas (live)
                                            │  • draft         │──► SelectionOverlay
                                            │  • tool settings │──► FloatingToolbar (ToolbarLayout)
                                            │  • undo/redo     │
                                            └────────┬─────────┘
                                                     │ Flattener.render(crop: selection)
                                                     ▼
                                     ExportService: copy · save to Photos · share · Files
```

- **One coordinate space.** All model geometry is in *image pixels* of the frozen
  screenshot. `ViewportMapping` converts view points ↔ image pixels (aspect-fit),
  so export is resolution-exact regardless of on-screen scale.
- **`EditorDocument`** owns the interaction state machine:
  `idle → selecting → (resizingSelection | movingSelection | drawing | movingAnnotation) → idle`.
  A drag begins a *draft* annotation; `end` validates it (Flameshot discards
  zero-length shapes) and commits it as one undo step.
- **Undo/redo** are value snapshots (`[Annotation]` + selection), capped at 100 —
  annotations are small value types, so snapshots are cheap and can't drift.
- **Rendering** is a single `AnnotationRenderer` used both live (SwiftUI `Canvas`
  via `withCGContext`) and for export (`Flattener`), so what you see is exactly
  what you export. Pixelate/invert results are cached per annotation.
- **Counter numbering** deviates deliberately from Flameshot: the next number is
  `max(existing) + 1`, so undoing a step frees its number.

## Input mapping (desktop → iPad)

| Flameshot | Ember |
| --- | --- |
| left-drag | Pencil or finger drag (coalesced touches for smooth strokes) |
| hover preview dot | Pencil hover (`UIHoverGestureRecognizer`, M2+ iPads) and trackpad pointer |
| right-click hold → radial picker | finger long-press, Pencil Pro **squeeze**, trackpad secondary click, or the swatch button; drag to choose, lift to commit |
| mouse wheel = size | side-panel stepper / slider, `[` / `]` |
| Shift = snap | hardware-keyboard ⇧ (`UIEvent.modifierFlags`) or the side-panel "Snap" toggle |
| Space = side panel | Space or the slider button → SwiftUI `.inspector` |
| Ctrl+Z / Ctrl+Shift+Z / Ctrl+C / Ctrl+S / Return / Esc | ⌘Z / ⇧⌘Z / ⌘C / ⌘S / Return / Esc |
| single-letter tool keys (P, D, A, S, R, C, M, T, B, I), G = colour | identical, plus N = counter, V = move |
| arrow keys move the selection, Ctrl+A select all, Delete removes object | arrow keys, ⌘A, Delete |
| — | **Pencil double-tap**: swap to previous tool. **Pencil-only drawing** (system setting): fingers move the selection / select objects instead of drawing |

## Toolbar

`ToolbarLayout` ports Flameshot's placement: buttons fill a row below the
selection, then a column to the right, a row above, a column to the left, and
finally rows inside the selection if it covers the screen. Buttons are 44 pt (Apple's
minimum touch target) instead of Flameshot's 30 px. The toolbar re-lays out live as
the selection moves.

## Export

`Flattener` draws the base image + annotations into a bitmap and crops to the
selection. `ExportService` offers:

- **Copy** → `UIPasteboard.general.image` (Flameshot's default "accept" action)
- **Save** → Photos via add-only permission (`PHPhotoLibrary.requestAuthorization(for: .addOnly)`)
- **Share** → `ShareLink` with a `Transferable` PNG rendered on demand
- **Save to Files** → `.fileExporter` with filename `yyyy-MM-dd_HH-mm.png`
  (Flameshot's `%F_%H-%M`)

## Not ported (yet)

Pin-to-screen (no floating windows on iPadOS — candidate: Picture-in-Picture or
Stage Manager window), imgur upload, magnifier, the large palette, text styles and
multi-line text, editing existing text, Shift+arrow selection resizing,
zoom/pan inside the editor, and a **Share Extension** so "Share → Ember" from the
system screenshot sheet opens the editor directly (the most natural next step).
