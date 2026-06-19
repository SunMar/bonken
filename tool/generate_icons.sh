#!/usr/bin/env bash
# Generate all launcher icons + web favicon from the SVG sources in
# assets/icon/.  The output PNGs are gitignored — run this script after
# editing the SVGs and before `flutter build`.
#
# Requires:
#   - rsvg-convert  (apt: librsvg2-bin)
#   - fc-match, fc-query  (apt: fontconfig)
#   - fvm  (local); CI passes --ci and uses PATH dart directly
#
# Usage:
#   ./tool/generate_icons.sh        # local (requires fvm)
#   ./tool/generate_icons.sh --ci   # CI (uses PATH dart, no fvm)
set -euo pipefail

ci=false
for arg in "$@"; do
  case "$arg" in
    --ci) ci=true ;;
    *) echo "error: unknown argument '$arg'" >&2; exit 2 ;;
  esac
done

# Resolve the script's real location (follows symlinks) so the script
# works no matter where it's invoked from or how it's linked.
cd "$(dirname -- "$(readlink -f -- "$0")")/.."
REPO="$PWD"

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "error: rsvg-convert not found (install with: sudo apt install librsvg2-bin)" >&2
  exit 1
fi
if ! command -v fc-match >/dev/null 2>&1 || ! command -v fc-query >/dev/null 2>&1; then
  echo "error: fc-match/fc-query not found (install with: sudo apt install fontconfig)" >&2
  exit 1
fi

# Local: always use fvm so the pinned SDK version is respected.
# CI: pass --ci; flutter-action puts the pinned SDK directly in PATH.
if $ci; then
  dart_cmd=(dart)
elif command -v fvm >/dev/null 2>&1; then
  dart_cmd=(fvm dart)
else
  echo "error: fvm not found — install fvm or pass --ci if running in CI" >&2
  exit 1
fi

# Build a self-contained fontconfig that exposes ONLY the fonts we ship
# with the project, so rsvg-convert renders deterministically regardless
# of which fonts happen to be installed system-wide:
#
#   - assets/google_fonts/<version>/  -> Roboto (Regular/Medium/Bold)
#                                        for the wordmark plus Arimo for the
#                                        suit symbols (♠ ♥ ♦ ♣) used in the
#                                        icon SVGs — the same TTFs the
#                                        Flutter app loads via google_fonts.
#
# Setting FONTCONFIG_FILE replaces the system fontconfig entirely, so any
# font NOT in this dir will not resolve.  That is the point: it
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

mkdir -p build
FONTCONFIG_DIR="$REPO/build/fontconfig"
mkdir -p "$FONTCONFIG_DIR/cache"
cat > "$FONTCONFIG_DIR/fonts.conf" <<EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <dir>$GFONTS_DIR</dir>
  <cachedir>$FONTCONFIG_DIR/cache</cachedir>
</fontconfig>
EOF
export FONTCONFIG_FILE="$FONTCONFIG_DIR/fonts.conf"

# Sanity-check that EVERY font we bundle under assets/google_fonts/<version>/
# resolves, through the sandbox fontconfig above, back to itself — never a
# system fallback. This is keyed on the files we actually ship (not on which
# weights the SVGs happen to use), so it stays exhaustive as cuts are added
# or removed. Each file is resolved by its own family + weight + slant; in a
# sandbox that exposes only these fonts, the match must be that same file.
#
# Tradeoff: this is asset-driven, so it does NOT verify that the families the
# SVGs *reference* are bundled — a future SVG naming an unbundled family/weight
# would silently fall back rather than erroring here. The SVGs currently use
# only Roboto and Arimo at weight 400 (both bundled); keep new glyphs within
# the shipped cuts. (See ARCHITECTURE.md §12 "Launcher icons → Font sandbox".)
for ttf in "$GFONTS_DIR"/*.ttf; do
  query="$(fc-query -f '%{family[0]}:weight=%{weight[0]}:slant=%{slant[0]}' "$ttf")"
  matched="$(fc-match -f '%{file}' "$query")"
  if [[ "$matched" != "$ttf" ]]; then
    echo "error: bundled font '$ttf'" >&2
    echo "       resolved to '$matched' (expected itself)." >&2
    echo "       The sandbox fontconfig at $FONTCONFIG_FILE is misconfigured," >&2
    echo "       or a font outside the repo is shadowing it." >&2
    exit 1
  fi
done

echo "==> Rendering source SVGs to 1024px PNGs"
rsvg-convert -w 1024 assets/icon/icon_bonken.svg              -o assets/icon/icon_bonken.png
rsvg-convert -w 72   assets/icon/icon_bonken.svg              -o assets/icon/icon_bonken_share.png
rsvg-convert -w 1024 assets/icon/icon_bonken_launcher.svg     -o assets/icon/icon_bonken_launcher.png
rsvg-convert -w 1024 assets/icon/icon_bonken_adaptive_fg.svg  -o assets/icon/icon_bonken_adaptive_fg.png
rsvg-convert -w 1024 assets/icon/icon_bonken_adaptive_bg.svg  -o assets/icon/icon_bonken_adaptive_bg.png
rsvg-convert -w 1024 assets/icon/icon_bonken_maskable.svg     -o assets/icon/icon_bonken_maskable.png

echo "==> Generating Android + web launcher icons"
"${dart_cmd[@]}" run flutter_launcher_icons

echo "==> Rendering PWA maskable icons (overrides flutter_launcher_icons output)"
# flutter_launcher_icons has no separate maskable_image_path for web, so we
# render icon_bonken_maskable.svg directly.  Its viewBox (-128 -128 1280 1280)
# matches icon_bonken_adaptive_fg.svg — both place the card at 50% of canvas.
# The native icon's android:inset="10%" (adaptive_icon_foreground_inset in
# pubspec.yaml) shrinks the foreground to 80% of the 108dp canvas, putting
# corners ~8-10px inside the 36dp adaptive safe zone.  The PWA corners land
# ~7px inside the maskable safe zone (40%×1280 = 512 SVG units, corners ~495).
# If the inset value or card geometry changes, recalculate both margins —
# see ARCHITECTURE.md §12 for details.
rsvg-convert -w 192 assets/icon/icon_bonken_maskable.svg -o web/icons/Icon-maskable-192.png
rsvg-convert -w 512 assets/icon/icon_bonken_maskable.svg -o web/icons/Icon-maskable-512.png

echo "==> Rendering web favicon (32px)"
rsvg-convert -w 32 assets/icon/icon_bonken.svg -o web/favicon.png

echo "==> Rendering iOS splash images"
rsvg-convert -w 200 assets/icon/icon_bonken_adaptive_fg.svg \
  -o ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png
rsvg-convert -w 400 assets/icon/icon_bonken_adaptive_fg.svg \
  -o ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@2x.png
rsvg-convert -w 600 assets/icon/icon_bonken_adaptive_fg.svg \
  -o ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png

echo "==> Rendering Android splash images"
rsvg-convert -w 200 assets/icon/icon_bonken_adaptive_fg.svg \
  -o android/app/src/main/res/drawable-mdpi/splash_logo.png
rsvg-convert -w 300 assets/icon/icon_bonken_adaptive_fg.svg \
  -o android/app/src/main/res/drawable-hdpi/splash_logo.png
rsvg-convert -w 400 assets/icon/icon_bonken_adaptive_fg.svg \
  -o android/app/src/main/res/drawable-xhdpi/splash_logo.png
rsvg-convert -w 600 assets/icon/icon_bonken_adaptive_fg.svg \
  -o android/app/src/main/res/drawable-xxhdpi/splash_logo.png
rsvg-convert -w 800 assets/icon/icon_bonken_adaptive_fg.svg \
  -o android/app/src/main/res/drawable-xxxhdpi/splash_logo.png

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
