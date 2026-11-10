#!/usr/bin/env bash
# Build and run EmberKit's tests on macOS.
#
# With full Xcode installed, `swift test` (inside Packages/EmberKit) or the
# Ember scheme's test action is all you need. This script is a fallback for
# machines with only the Command Line Tools, where SwiftPM can't link package
# manifests. It compiles the module and the Swift Testing suites with swiftc.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/Packages/EmberKit"
OUT="${TMPDIR:-/tmp}/emberkit-tests"
DEV="$(xcode-select -p)"
if [[ "$DEV" == *CommandLineTools* ]]; then
  FRAMEWORKS="$DEV/Library/Developer/Frameworks"
  PLUGINS="$DEV/usr/lib/swift/host/plugins/testing"
  DEVLIB="$DEV/Library/Developer/usr/lib"
else
  PLAT="$DEV/Platforms/MacOSX.platform/Developer"
  FRAMEWORKS="$PLAT/Library/Frameworks"
  PLUGINS="$DEV/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins/testing"
  DEVLIB="$PLAT/usr/lib"
fi
TARGET="$(uname -m)-apple-macosx14.0"

mkdir -p "$OUT"
cd "$PKG"

swiftc -swift-version 6 -target "$TARGET" -enable-testing \
  -emit-module -emit-library -module-name EmberKit \
  -emit-module-path "$OUT/EmberKit.swiftmodule" \
  -o "$OUT/libEmberKit.dylib" \
  -Xlinker -install_name -Xlinker @rpath/libEmberKit.dylib \
  $(find Sources -name '*.swift')

cat > "$OUT/main.swift" <<'EOF'
import Testing
@main struct Runner { static func main() async { await Testing.__swiftPMEntryPoint() as Never } }
EOF

swiftc -swift-version 6 -target "$TARGET" -parse-as-library -module-name EmberKitTests \
  -I "$OUT" -L "$OUT" -lEmberKit \
  -F "$FRAMEWORKS" -framework Testing -plugin-path "$PLUGINS" \
  -Xlinker -rpath -Xlinker "$OUT" \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$DEVLIB" \
  -o "$OUT/tests" Tests/EmberKitTests/*.swift "$OUT/main.swift"

"$OUT/tests" "$@"
