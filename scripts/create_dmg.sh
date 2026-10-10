#!/usr/bin/env bash
# scripts/create_dmg.sh
# Creates a production-quality, drag-and-drop macOS Disk Image (DMG) for Trackpad Toggle.
#
# Features:
#   • Builds the app if needed
#   • Modern macOS diskutil image create with hdiutil fallback
#   • Proper Applications symlink for drag-and-drop installation
#   • Verifies the generated DMG by attaching, inspecting, and ejecting
#
# Usage:
#   ./scripts/create_dmg.sh
#   ./scripts/create_dmg.sh --open-on-complete

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
APP_PATH="$BUILD_DIR/TrackpadToggle.app"
DMG_PATH="$BUILD_DIR/TrackpadToggle.dmg"
VOLUME_NAME="Trackpad Toggle"

echo "=================================================="
echo "    Packaging Trackpad Toggle as macOS Disk Image"
echo "=================================================="

# ── 1. Ensure App Is Built ──────────────────────────────────────────────────
if [[ ! -d "$APP_PATH" ]]; then
    echo "▶  App bundle not found at $APP_PATH. Building now…"
    (cd "$PROJECT_ROOT" && bash build.sh)
fi

# Verify app bundle integrity
if [[ ! -f "$APP_PATH/Contents/MacOS/TrackpadToggle" ]]; then
    echo "❌  Invalid app bundle: missing executable."
    exit 1
fi
if [[ ! -f "$APP_PATH/Contents/Info.plist" ]]; then
    echo "❌  Invalid app bundle: missing Info.plist."
    exit 1
fi

echo "✓ Verified app bundle: $APP_PATH"

# ── 2. Prepare Staging Directory ─────────────────────────────────────────────
STAGING_DIR="$BUILD_DIR/dmg_staging"
rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"

echo "▶  Copying app bundle to staging…"
cp -R "$APP_PATH" "$STAGING_DIR/TrackpadToggle.app"

echo "▶  Creating Applications folder symlink…"
ln -s /Applications "$STAGING_DIR/Applications"

# ── 3. Build Disk Image ──────────────────────────────────────────────────────
echo "▶  Creating compressed Disk Image ($DMG_PATH)…"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

rm -rf "$STAGING_DIR"

# ── 4. Verify Disk Image Integrity ──────────────────────────────────────────
echo "▶  Verifying generated DMG integrity…"
VERIFY_MOUNT="/tmp/trackpad_toggle_dmg_verify_$$"
mkdir -p "$VERIFY_MOUNT"

ATTACH_DEV="$(hdiutil attach -mountpoint "$VERIFY_MOUNT" -nobrowse -readonly "$DMG_PATH" 2>/dev/null | grep -E '^/dev/' | head -1 | awk '{print $1}' || true)"

if [[ -d "$VERIFY_MOUNT/TrackpadToggle.app" && -L "$VERIFY_MOUNT/Applications" ]]; then
    echo "✓ Verified DMG structure: contains TrackpadToggle.app and Applications symlink"
else
    echo "⚠️  Verification warning: expected files not found at mount point"
fi

# Eject verification mount
if [[ -n "$ATTACH_DEV" ]]; then
    diskutil eject "$ATTACH_DEV" >/dev/null 2>&1 || hdiutil detach "$ATTACH_DEV" -force >/dev/null 2>&1 || true
else
    diskutil eject "$VERIFY_MOUNT" >/dev/null 2>&1 || hdiutil detach "$VERIFY_MOUNT" -force >/dev/null 2>&1 || true
fi
rm -rf "$VERIFY_MOUNT"

# ── 5. Summary ───────────────────────────────────────────────────────────────
DMG_SIZE="$(du -h "$DMG_PATH" | cut -f1)"
echo ""
echo "=================================================="
echo "✅  Disk Image ready: $DMG_PATH ($DMG_SIZE)"
echo "=================================================="
echo ""
echo "Installation experience for users:"
echo "  1. Double-click TrackpadToggle.dmg in Finder."
echo "  2. Drag TrackpadToggle.app into the Applications folder."
echo "  3. Open from Applications or Spotlight (⌘ + Space)."
echo ""

if [[ "${1:-}" == "--open-on-complete" || "${1:-}" == "--open" ]]; then
    echo "▶  Mounting DMG in Finder for preview…"
    open "$DMG_PATH"
fi
