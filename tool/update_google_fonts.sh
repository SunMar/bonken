#!/usr/bin/env bash
# Download the Roboto Light/Regular/Medium/Bold font files used by the app
# from Google Fonts' CDN, into assets/google_fonts/<version>/.
#
# The "<version>" is the currently-resolved google_fonts package version
# (read from pubspec.lock) — re-run this script after bumping google_fonts
# in pubspec.yaml + `flutter pub get`, then update the asset path in
# pubspec.yaml and the import path in lib/main.dart, and delete the old
# version directory.
#
# Why this exists: google_fonts is configured with allowRuntimeFetching=false
# so the app works fully offline.  Fonts must therefore be bundled as assets,
# and each google_fonts release ships its own per-font hashes (the URL is
# https://fonts.gstatic.com/s/a/<hash>.ttf).  This script pulls those hashes
# out of the package source in the pub cache, so the bundled .ttf files
# always match what google_fonts expects to load.
#
# Usage: ./tool/update_google_fonts.sh

set -euo pipefail

cd "$(dirname "$0")/.."

# 1. Resolve the google_fonts version from pubspec.lock.
version="$(awk '/^  google_fonts:/{flag=1; next} flag && /^    version:/{gsub(/"/,"",$2); print $2; exit}' pubspec.lock)"
if [[ -z "${version:-}" ]]; then
  echo "Could not determine google_fonts version from pubspec.lock" >&2
  exit 1
fi
echo "Using google_fonts version: $version"

# 2. Locate the package source in the pub cache.
pkg_dir="$HOME/.pub-cache/hosted/pub.dev/google_fonts-$version"
if [[ ! -d "$pkg_dir" ]]; then
  echo "google_fonts package not found at $pkg_dir" >&2
  echo "Run 'flutter pub get' first." >&2
  exit 1
fi
roboto_src="$pkg_dir/lib/src/google_fonts_parts/part_r.dart"

# 3. Extract Roboto hashes for the four weights we bundle.
# The Roboto block lists weights in the order w100..w900 (normal style first,
# then italics).  We want indices 3,4,5,7 = w300,w400,w500,w700 normal.
mapfile -t hashes < <(
  awk "/^  static TextStyle roboto\\(/,/fontFamily: 'Roboto',/" "$roboto_src" \
    | grep -oE "'[0-9a-f]{64}'" \
    | tr -d "'"
)
if (( ${#hashes[@]} < 9 )); then
  echo "Failed to parse Roboto hashes from $roboto_src" >&2
  exit 1
fi
declare -A weights=(
  [Light]="${hashes[2]}"    # w300
  [Regular]="${hashes[3]}"  # w400
  [Medium]="${hashes[4]}"   # w500
  [Bold]="${hashes[6]}"     # w700
)

# 4. Download each .ttf into the versioned asset directory.
out_dir="assets/google_fonts/$version"
mkdir -p "$out_dir"
for weight in Light Regular Medium Bold; do
  hash="${weights[$weight]}"
  url="https://fonts.gstatic.com/s/a/$hash.ttf"
  dest="$out_dir/Roboto-$weight.ttf"
  echo "  -> $dest  ($hash)"
  curl -fsSL "$url" -o "$dest"
done

echo
echo "Done.  Next steps:"
echo "  - Update the asset path in pubspec.yaml to: assets/google_fonts/$version/"
echo "  - Update the version comment(s) in pubspec.yaml"
echo "  - Delete any old assets/google_fonts/<other-version>/ directories"
