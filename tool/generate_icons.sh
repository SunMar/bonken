#!/usr/bin/env bash
# Generate all launcher icons + web favicon from the SVG sources in
# assets/icon/.  The output PNGs are gitignored — run this script after
# editing the SVGs and before `flutter build`.
#
# Requires:
#   - rsvg-convert  (apt: librsvg2-bin)
#   - flutter / dart
#
# Usage:
#   ./tool/generate_icons.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "error: rsvg-convert not found (install with: sudo apt install librsvg2-bin)" >&2
  exit 1
fi

# The wordmark in icon_bonken.svg uses Roboto Black.  fontconfig must know
# about it or rsvg-convert will silently fall back to a different font and
# the rendered PNG will not match the SVG preview.
if command -v fc-list >/dev/null 2>&1; then
  fonts="$(fc-list : family)"
  if ! grep -qi 'roboto' <<<"$fonts"; then
    echo "error: Roboto font not installed (install with: sudo apt install fonts-roboto)" >&2
    exit 1
  fi
fi

echo "==> Rendering source SVGs to 1024px PNGs"
rsvg-convert -w 1024 assets/icon/icon_bonken.svg              -o assets/icon/icon_bonken.png
rsvg-convert -w 1024 assets/icon/icon_bonken_adaptive_fg.svg  -o assets/icon/icon_bonken_adaptive_fg.png
rsvg-convert -w 1024 assets/icon/icon_bonken_adaptive_bg.svg  -o assets/icon/icon_bonken_adaptive_bg.png

echo "==> Generating Android + web launcher icons"
dart run flutter_launcher_icons

echo "==> Rendering web favicon (32px)"
rsvg-convert -w 32 assets/icon/icon_bonken.svg -o web/favicon.png

echo "==> Rendering Play Store listing icon (512px)"
mkdir -p build
rsvg-convert -w 512 assets/icon/icon_bonken.svg -o build/play-store-icon-512.png

echo "==> Rendering Play Store feature graphic (1024x500)"
rsvg-convert -w 1024 -h 500 assets/icon/feature_graphic.svg -o build/play-store-feature-1024x500.png

echo "Done."
echo
echo "Play Console listing assets:"
echo "  App icon (512x512):           build/play-store-icon-512.png"
echo "  Feature graphic (1024x500):   build/play-store-feature-1024x500.png"
echo "  Screenshots: capture from a running build"
