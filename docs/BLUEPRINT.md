# Flameshot feature blueprint

Behavioural spec extracted for the iPadOS rebuild ("Ember"). It describes **what
Flameshot does**, not how its C++ is written; Ember's Swift code is an independent
implementation of this behaviour.

## Sources examined

| Source | Identity | Method |
| --- | --- | --- |
| `Flameshot-15.0.0-macos-arm64.dmg` | sha256 `ff2f63fb…df3d`, 698 entries | REA `inspect-artifact` (inventory) + read-only mount |
| `Flameshot.app` | `org.flameshot.Flameshot` 15.0.0, Mach-O arm64, `LSUIElement` (menu-bar agent), macOS ≥ 14 | `Info.plist`, `codesign`, `strings` |
| `flameshot-org/flameshot` | `main` @ `e8092a1` (2026-11-07) | source reading (`src/tools`, `src/widgets/capture`, `src/utils/confighandler.cpp`) |

**Shipped binary vs. source.** The bundle is Qt 6 (`QtWidgets`, `QtGui`, `QtSvg`,
`QtNetwork`, `QtDBus`, `QtQuick`…) plus image codecs (png, jpeg, webp, tiff). The
binary's user-visible tool names — *Pencil, Line, Arrow, Rectangle, Circle, Marker,
Text, Pixelate, Invert, Circle Counter, Move, Undo, Redo, Copy, Save, Pin Tool* —
match the `CaptureTool::Type` enum in source, so the source is an accurate
description of the shipped 15.0.0 behaviour. No imgur uploader strings are relevant
to this port. Nothing in the bundle (Qt widgets, global hotkeys, frameless
full-screen overlay windows) is reusable on iPadOS.

> **Licence note.** Flameshot is GPL-3.0-or-later and its source was read to
> write this spec, so Ember is *not* a strict legal clean room. Ember copies no
> code, icons or strings — only behaviour and numeric parameters. If you intend
> to ship closed-source, get legal advice; the alternative is to publish Ember
> under GPLv3 (which has its own App Store friction). Don't use the Flameshot
> name or logo.

## 1. Capture workflow (`CaptureWidget`)

1. Hotkey → the whole screen is grabbed and shown **frozen** in a borderless
   full-screen window.
2. Everything outside the selection is dimmed with black at `contrastOpacity`
   **190/255**. The selection border is a 1 px line in the UI colour, with round
   handles.
3. User drags a **selection rectangle**. It has 8 resize handles (corners + edge
   midpoints) and can be dragged to move. Arrow keys move it 1 px, Shift+arrows
   resize, Ctrl+Shift+arrows resize symmetrically, Ctrl+A selects everything.
4. Once a selection exists, the **toolbar buttons appear around it** (§2).
5. User annotates; every finished shape is pushed to an undo stack (limit **100**).
6. Finish: **Enter** = accept (copy + close), **Ctrl+C** copy, **Ctrl+S** save,
   **Esc / Ctrl+Q** exit. Output is the frozen image **with annotations, cropped
   to the selection**.
7. **Space** toggles the side panel (colour, size, tool settings, "grab colour").
   **Right-click hold** opens the radial colour picker (§3).
   **Mouse wheel** changes the active tool's size (thickness or font size).
8. Hover preview: before drawing, two-point tools show a dot of the current
   colour/size under the cursor; the counter shows its bubble.
9. Annotations can be **selected** (click on them when no drawing tool is active),
   moved, and deleted with Backspace/Delete. Selected objects get a black 3 px +
   white 1 px dotted outline.

## 2. Toolbar (`CaptureToolButton`, `ButtonHandler`)

**Default order** (`buttonTypeOrder`):

| # | Tool | Key | Ember tool |
| -- | --- | --- | --- |
| 0 | Pencil (freehand) | P | `pencil` |
| 1 | Line ("Drawer") | D | `line` |
| 2 | Arrow | A | `arrow` |
| 3 | Rectangle **outline** (`TYPE_SELECTION`) | S | `rectangleOutline` |
| 4 | Rectangle **filled** (`TYPE_RECTANGLE`) | R | `rectangleFilled` |
| 5 | Circle / ellipse outline | C | `ellipse` |
| 6 | Marker (highlighter) | M | `marker` |
| 7 | Text | T | `text` |
| 8 | Pixelate | B | `pixelate` |
| 9 | Invert | I | `invert` |
| 10 | Circle counter | – | `counter` |
| 12 | Move selection | Ctrl+M | finger drag on selection |
| 13–14 | Undo / Redo | Ctrl+Z / Ctrl+Shift+Z | ⌘Z / ⇧⌘Z |
| 15–16 | Copy / Save | Ctrl+C / Ctrl+S | ⌘C / ⌘S |
| 18 | Accept | Return | Done |
| 19–20 | Exit / Pin | Ctrl+Q / – | Close / (not ported) |
| 22–23 | Size + / Size − | – | stepper in side panel |

Note the naming trap: Flameshot's "Selection" tool draws an **outlined**
rectangle, and its "Rectangle" tool draws a **filled** one with rounded corners.

**Placement algorithm** (`ButtonHandler::updatePosition`). Buttons are square
(`buttonBaseSize`, ~30 px × DPI scale) with a separator gap; their pitch is
`buttonExtendedSize`. The handler fills buttons into "blocks" in this priority:

1. a row **below** the selection, centred on it, if there is room below;
2. a column on the **right**, then a row **above**, then a column on the **left**;
3. if the selection is hugging screen edges on every side, the remaining buttons
   go **inside** the selection, in rows from its bottom edge upward.

Each block holds as many buttons as fit along that side
(`(side + separator) / buttonExtendedSize`); leftover buttons spill into the next
block. A selection smaller than one button is treated as one button big.

## 3. Colour picker (`ColorPicker`, `ColorPickerWidget`)

- **Radial** layout: N swatches on a circle, starting at 90° (top) and stepping
  `360/N` degrees. Radius = `3·N + buttonBaseSize`; swatch size =
  `0.6 · buttonBaseSize`.
- Opens on right-button press at the cursor, follows the pointer (hover selects),
  and **commits on release** — a single press-drag-release gesture.
- Default small palette: *[custom], dark red, red, yellow, green, dark green,
  cyan, blue, magenta, dark magenta*. Slot 0 (`QColor()`) opens a full colour
  dialog. Default draw colour **red**.
- A larger 3×17 palette is an option (`predefinedColorPaletteLarge`).

## 4. Tool parameters

Two independent sizes: **thickness** (default **3**) for shapes and **font size**
(default **8**) for text. Mouse wheel adjusts whichever the active tool uses.

All two-point tools record `first` = press point and `second` = current point.
Holding **Shift** snaps the vector (`AbstractTwoPointTool::adjustedVector`):

- *Orthogonal + diagonal* tools (line, arrow, marker): snap to the nearest of 8
  directions (0°, 45°, 90°…); diagonals use `x' = (x − y)/2, y' = −x'` (or the
  `+` variant) to force |x| = |y|.
- *Diagonal-only* tools (rectangles, ellipse): snap to a square/circle.
- A shape is valid only if `first ≠ second`; zero-length shapes are discarded.

### Pencil
Freehand polyline of every move point, `color`, `thickness`, round caps/joins.

### Line
Straight line `first → second`.

### Arrow
- Head length `H = 18 + 4·t`, head half-base `W = (10 + 2·t)/2` (`t` = thickness).
- The shaft is **shortened** so its square end doesn't poke through the tip:
  shaft length `= L + 2t − H`; if the arrow is shorter than `H − 2t`, the head
  scales down to `L + 2t` and the shaft collapses to `t/4`.
- Head = filled triangle *tip, base-left, base-right*.
- Style 1 ("curved") uses a notched head: base edges joined to a notch `≤ 0.45·`
  head length deep via quadratic curves, flat-cap shaft overlapping the notch by 1 px.
- The tip is at the **release point** (`second`) by default; option
  `reverseArrow` puts it at the press point instead. (Careful: the source names
  the press point `head` even though the tip is drawn at the other end.)

### Rectangle outline ("Selection" tool)
Stroked rect, square caps, mitre joins.

### Rectangle filled ("Rectangle" tool)
Rect grown by `offset = round(t/2 + 0.5)` each side, **filled**, corner radius `t`
(sharp when `t == 0`).

### Circle
Stroked ellipse inscribed in the `first/second` rect.

### Marker
Line `first → second` with **multiply** blending at **35 % opacity** (a
highlighter: dark text stays readable through it). The pen is **14 wider than
the thickness** (`thickness + 14`), so at the default thickness 3 it is a 17 px
band that covers a line of text.

### Text
- Tap places a live text box (editable widget) at the point; commit on
  click-outside or Ctrl+Return.
- Rendered with 5 px padding, current colour, font size = text size. Alignment
  and bold/italic/underline/strike are configurable in the side panel.

### Circle counter (numbered steps)
- Each placement takes the shared counter value and increments it
  (bounded **1…999**). The counter is document state, so undo **does not**
  rewind it in Flameshot.
- Bubble radius `r = t + 15`. Filled circle in `color`; if the outline option is
  on (default **true**) an extra ring of `r + 2` is drawn in the anti-contrast
  colour (white for dark fills, black for light) with a contrast-colour pen.
- Number: bold, pixel size `r`, centred in an `r × r` box, shrunk until it fits;
  text colour = contrast colour (white on dark, black on light).
- **Pointer tail:** dragging after the press stretches a filled kite from the
  bubble centre to the drag point (only when the drag is longer than `r`): the
  quad *centre → centre + n·r → second → centre − n·r* where `n` is the unit
  normal of the drag line.

### Pixelate (redaction)
Rect from `first/second`, clipped to the image. Block count:
`w' = w · 0.5/(t + 1)`, `h' = h · 0.5/(t + 1)` (min 1).

- **Secure mode (default):** the pixels *inside* the rect are **never sampled**.
  The output is synthesised from the four 1-px fringe strips just outside each
  edge: for each block `(x, y)`, sample each strip at the proportional position
  plus Gaussian jitter (σ = `5t + 1`, deterministic PRNG seed 42), blend
  left/right by `x/w'` and top/bottom by `y/h'`, average the two blends, add
  σ = 0.1 noise, then upscale with nearest-neighbour. Result: a plausible smear
  that leaks no information about the redacted content.
  *(In the source the horizontal/vertical weight uses integer division and is
  always 0.5; Ember uses the same 50/50 blend.)*
- **Insecure mode** (`insecurePixelate`): `t ≤ 1` → Gaussian blur (radius 10,
  applied twice); otherwise classic down-scale (smooth) then up-scale (blocky).
  This *is* reversible to a degree and is opt-in.

### Invert
Pixels in the rect, colour-inverted.

## 5. Rendering order & export

Annotations are painted in creation order over the frozen screenshot; pixelate
and invert read from the **original** screenshot (not from earlier annotations).
Export = flatten base + annotations, crop to selection, then copy / save PNG /
upload. Default filename pattern `%F_%H-%M` (date_hour-minute).

## 6. Defaults summary

| Setting | Default |
| --- | --- |
| UI colour / contrast UI colour | rgb(116,0,150) / rgb(39,0,50) |
| Dim opacity outside selection | 190 / 255 |
| Draw colour | red |
| Thickness / font size | 3 / 8 |
| Undo limit | 100 |
| Counter outline | on |
| Secure pixelate | on |
| Magnifier | off |
