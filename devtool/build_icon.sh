#!/bin/bash
# Generates a macOS .icns file from a high-resolution PNG image.
#
# Usage:
#   ./devtool/build_icon.sh [input.png] [output.icns]
#   ./devtool/build_icon.sh                          # defaults: icon.png → mac/MarsinDictationApp/AppIcon.icns
#
# Requires: sips, iconutil (built-in on macOS)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

INPUT="${1:-$ROOT_DIR/icon.png}"
OUTPUT="${2:-$ROOT_DIR/mac/MarsinDictationApp/AppIcon.icns}"

if [[ ! -f "$INPUT" ]]; then
    echo "❌ Input file not found: $INPUT"
    exit 1
fi

echo "▸ Building macOS icon from: $INPUT"

# Create temporary iconset directory
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"

# Generate all required sizes
# macOS requires these exact filenames in the .iconset
SIZES=(16 32 64 128 256 512 1024)
NAMES=(
    "icon_16x16.png:16"
    "icon_16x16@2x.png:32"
    "icon_32x32.png:32"
    "icon_32x32@2x.png:64"
    "icon_128x128.png:128"
    "icon_128x128@2x.png:256"
    "icon_256x256.png:256"
    "icon_256x256@2x.png:512"
    "icon_512x512.png:512"
    "icon_512x512@2x.png:1024"
)

for entry in "${NAMES[@]}"; do
    name="${entry%%:*}"
    size="${entry##*:}"
    sips -z "$size" "$size" "$INPUT" --out "$ICONSET/$name" > /dev/null 2>&1
    echo "  ✔ $name (${size}x${size})"
done

# Convert iconset to .icns
iconutil -c icns "$ICONSET" -o "$OUTPUT"

# Cleanup
rm -rf "$(dirname "$ICONSET")"

echo "✔ Icon created: $OUTPUT"
