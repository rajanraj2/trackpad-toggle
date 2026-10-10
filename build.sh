#!/usr/bin/env bash
# build.sh — compiles TrackpadToggle.app from sources using swiftc.
# Run from the TrackpadToggle/ directory or pass the path as $1.
#
# Usage:
#   cd TrackpadToggle && ./build.sh          # builds in ./build/
#   ./build.sh --open                        # builds and opens the app

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/Sources"
RES="$SCRIPT_DIR/Resources"
BUILD="$SCRIPT_DIR/build"
APP="$BUILD/TrackpadToggle.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"

# ── macOS SDK ────────────────────────────────────────────────────────────────
SDK="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
if [[ -z "$SDK" ]]; then
  echo "❌  Xcode Command Line Tools not found. Install with: xcode-select --install"
  exit 1
fi
MACOS_VER="$(sw_vers -productVersion | cut -d. -f1-2)"
echo "▶  Building for macOS $MACOS_VER (SDK: $SDK)"

# ── Create .app bundle skeleton ──────────────────────────────────────────────
rm -rf "$APP"
mkdir -p "$MACOS" "$CONTENTS/Resources"

# ── Compile ──────────────────────────────────────────────────────────────────
SWIFT_SOURCES=(
  "$SRC/TrackpadState.swift"
  "$SRC/Preferences.swift"
  "$SRC/PermissionsManager.swift"
  "$SRC/TrackpadController.swift"
  "$SRC/HotKeyManager.swift"
  "$SRC/MenuBarController.swift"
  "$SRC/SettingsWindowController.swift"
  "$SRC/AppDelegate.swift"
  "$SRC/main.swift"
)

echo "▶  Compiling Swift sources…"
swiftc \
  -sdk "$SDK" \
  -target "arm64-apple-macos${MACOS_VER}" \
  -O \
  -module-name TrackpadToggle \
  -framework AppKit \
  -framework Carbon \
  -framework ApplicationServices \
  -framework IOKit \
  -framework CoreFoundation \
  -framework SwiftUI \
  "${SWIFT_SOURCES[@]}" \
  -o "$MACOS/TrackpadToggle"

echo "▶  Copying resources…"
cp "$RES/Info.plist" "$CONTENTS/Info.plist"

# ── Ad-hoc sign (required to launch on macOS without notarisation) ────────────
echo "▶  Ad-hoc signing…"
codesign --force --sign - \
  --entitlements "$RES/TrackpadToggle.entitlements" \
  "$APP"

echo ""
echo "✅  Built: $APP"
echo ""
echo "To launch:"
echo "  open '$APP'"
echo ""
echo "First launch: macOS will ask for Accessibility and Input Monitoring."
echo "Grant both in System Settings → Privacy & Security."

# ── Optional --open flag ─────────────────────────────────────────────────────
if [[ "${1:-}" == "--open" ]]; then
  echo "▶  Opening app…"
  open "$APP"
fi
