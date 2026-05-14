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

# Resolve the script's real location (follows symlinks) so the script
# works no matter where it's invoked from or how it's linked.
cd "$(dirname -- "$(readlink -f -- "$0")")/.."
REPO="$PWD"

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "error: rsvg-convert not found (install with: sudo apt install librsvg2-bin)" >&2
  exit 1
fi

# Build a self-contained fontconfig that exposes ONLY the fonts we ship
# with the project, so rsvg-convert renders deterministically regardless
# of which fonts happen to be installed system-wide:
#
#   - assets/google_fonts/<version>/  -> Roboto Regular/Medium/Bold/Light
#                                        (the same TTFs the Flutter app
#                                        loads via the google_fonts pkg)
#   - assets/dejavu/<version>/        -> DejaVuSans.ttf for the suit
#                                        symbols (♠ ♥ ♦ ♣) used in the
#                                        icon SVGs (same .ttf the runtime
#                                        app loads via pubspec fonts:)
#
# Setting FONTCONFIG_FILE replaces the system fontconfig entirely, so any
# font NOT in these two dirs will not resolve.  That is the point: it
# guarantees byte-identical PNGs across machines and CI.

# Discover the bundled google_fonts asset dir from pubspec.yaml so this
# script doesn't need a hardcoded version number — just keep pubspec's
# `assets:` entry as the single source of truth.  Picks the first match
# of the form `assets/google_fonts/<anything>/`.
GFONTS_REL="$(sed 's/#.*//' pubspec.yaml | grep -oE 'assets/google_fonts/[^/[:space:]]+/?' | head -1 | sed 's:/$::')"
if [[ -z "$GFONTS_REL" || ! -d "$REPO/$GFONTS_REL" ]]; then
  echo "error: could not locate google_fonts asset dir from pubspec.yaml" >&2
  echo "       (looked for an 'assets/google_fonts/<version>/' entry)" >&2
  exit 1
fi
GFONTS_DIR="$REPO/$GFONTS_REL"

# Same pattern for DejaVu — read the versioned dir from the `fonts:`
# block in pubspec.yaml so tool/update_fonts.sh has a single source of
# truth for the version (the asset path under flutter.fonts).
DEJAVU_REL="$(sed 's/#.*//' pubspec.yaml | grep -oE 'assets/dejavu/[^/[:space:]]+' | head -1)"
if [[ -z "$DEJAVU_REL" || ! -d "$REPO/$DEJAVU_REL" ]]; then
  echo "error: could not locate dejavu asset dir from pubspec.yaml" >&2
  echo "       (looked for an 'assets/dejavu/<version>/' path)" >&2
  exit 1
fi
DEJAVU_DIR="$REPO/$DEJAVU_REL"

mkdir -p build
FONTCONFIG_DIR="$REPO/build/fontconfig"
mkdir -p "$FONTCONFIG_DIR/cache"
cat > "$FONTCONFIG_DIR/fonts.conf" <<EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <dir>$GFONTS_DIR</dir>
  <dir>$DEJAVU_DIR</dir>
  <cachedir>$FONTCONFIG_DIR/cache</cachedir>
</fontconfig>
EOF
export FONTCONFIG_FILE="$FONTCONFIG_DIR/fonts.conf"

# Sanity-check the two families the SVGs reference actually resolve to
# files inside the repo.  fc-match prints the matched font filename.
if command -v fc-match >/dev/null 2>&1; then
  for family in "Roboto" "Roboto:weight=200" "DejaVu Sans"; do
    matched="$(fc-match -f '%{file}' "$family")"
    case "$matched" in
      "$REPO"/*) ;;
      *)
        echo "error: font '$family' resolved to '$matched' (outside repo)" >&2
        echo "       The bundled fontconfig at $FONTCONFIG_FILE is misconfigured." >&2
        exit 1
        ;;
    esac
  done
fi

echo "==> Rendering source SVGs to 1024px PNGs"
rsvg-convert -w 1024 assets/icon/icon_bonken.svg              -o assets/icon/icon_bonken.png
rsvg-convert -w 1024 assets/icon/icon_bonken_launcher.svg     -o assets/icon/icon_bonken_launcher.png
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
