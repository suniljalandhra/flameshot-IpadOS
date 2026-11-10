# Ember

A native iPadOS screenshot annotator (SwiftUI + ReplayKit) that recreates
[Flameshot](https://github.com/flameshot-org/flameshot)'s workflow: freeze the
screen, drag a selection, annotate with a toolbar that wraps around the selection,
and copy, save or share the result.

- **[docs/BLUEPRINT.md](docs/BLUEPRINT.md)** — Flameshot's behaviour, extracted
  from the 15.0.0 macOS DMG and the source: toolbar order and placement, colour
  wheel, every tool's geometry and defaults, secure pixelation.
- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — how Ember maps that onto
  iPadOS: capture paths, modules, state, input mapping, export.

## Requirements

- Xcode 16 or newer, with the iOS 17+ SDK
- An iPad (or iPad simulator) running iPadOS 17+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) only if you change
  `project.yml` (`brew install xcodegen`)

## Getting started

1. Open `Ember.xcodeproj`.
2. In `project.yml` (then run `xcodegen generate`), or in each target's
   *Signing & Capabilities* tab, set:
   - `DEVELOPMENT_TEAM` → your team
   - `APP_BUNDLE_ID` → e.g. `com.yourname.ember` (the broadcast extension
     becomes `<APP_BUNDLE_ID>.Broadcast` automatically)
   - `APP_GROUP_ID` → e.g. `group.com.yourname.ember`, and enable it under App
     Groups for **both** targets
3. Choose the **Ember** scheme and an iPad, then Run.

Screen broadcast only works on a real device; the Photos, picker and paste
sources work in the simulator.

## Tests

The editor's behaviour (geometry, rendering, undo, redaction, toolbar layout)
lives in the `EmberKit` package and is covered by 36 Swift Testing tests that run
on a Mac:

```bash
cd Packages/EmberKit && swift test
```

Or in Xcode: Product › Test on the Ember scheme. On a Mac with only the Command
Line Tools, where SwiftPM can't link manifests, use:

```bash
./scripts/test-emberkit.sh
```

## Layout

```
App/                 iPad app (SwiftUI; UIKit for Pencil / touch input)
BroadcastExtension/  ReplayKit broadcast upload extension
Packages/EmberKit/   model, geometry, rendering, undo (no UIKit) + tests
docs/                blueprint and architecture
project.yml          XcodeGen spec for Ember.xcodeproj
```

## Licence note

Flameshot is GPL-3.0. Ember copies no Flameshot code, icons or text, but its
behaviour was specified by reading Flameshot's source, so it isn't a strict
clean-room implementation. Get advice before shipping it closed-source, and don't
use the Flameshot name or logo. See [BLUEPRINT.md](docs/BLUEPRINT.md).
