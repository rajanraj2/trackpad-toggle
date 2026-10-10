#!/usr/bin/env bash
# Double-click this file in Finder to build and install Trackpad Toggle!
# No Terminal typing required.

set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

echo "========================================"
echo "    Installing Trackpad Toggle for macOS"
echo "========================================"
echo ""

bash build.sh --install

echo ""
echo "========================================"
echo "✓ Trackpad Toggle is now installed!"
echo "  You can open it anytime using Spotlight:"
echo "  Press ⌘ + Space and type 'Trackpad Toggle'"
echo "========================================"
echo ""
read -p "Press Return to finish..."
