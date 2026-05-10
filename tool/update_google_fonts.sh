#!/usr/bin/env bash
# Upgrade the bundled google_fonts package + its Roboto font assets in lock-step.
#
# google_fonts is pinned to an exact version in pubspec.yaml (no caret) so a
# plain `flutter pub upgrade` cannot bump it without also re-downloading the
# matching font hashes — every google_fonts release ships its own per-font
# hashes embedded in the source (URL: https://fonts.gstatic.com/s/a/<hash>.ttf)
# and we run with allowRuntimeFetching=false, so the .ttf files bundled under
# assets/google_fonts/<version>/ MUST match the package version.
#
# This script does the whole upgrade atomically:
#   1. Reads the current pinned version from pubspec.yaml.
#   2. Temporarily relaxes the constraint to ^current and runs
#      `flutter pub upgrade google_fonts` to discover the latest compatible
#      version.
#   3. If the version changed:
#        a. Re-pins pubspec.yaml to the new exact version.
#        b. Updates the assets/google_fonts/<version>/ path in pubspec.yaml.
#        c. Downloads the matching Roboto Light/Regular/Medium/Bold .ttf files.
#        d. Deletes the old assets/google_fonts/<old-version>/ directory.
#      Otherwise restores the pinned constraint and exits.
#
# Usage: ./tool/update_google_fonts.sh

set -euo pipefail

cd "$(dirname "$0")/.."

pubspec="pubspec.yaml"

# Read the currently-pinned version from pubspec.yaml.  Accepts either a
# pinned version (`google_fonts: 8.1.0`) or a caret constraint
# (`google_fonts: ^8.1.0`) — the caret form is what we briefly write below.
read_pubspec_version() {
  awk '
    /^[[:space:]]*google_fonts:[[:space:]]*\^?[0-9]/ {
      v = $2
      sub(/^\^/, "", v)
      print v
      exit
    }
  ' "$pubspec"
}

old_version="$(read_pubspec_version)"
if [[ -z "${old_version:-}" ]]; then
  echo "Could not find a 'google_fonts: <version>' line in $pubspec" >&2
  exit 1
fi
echo "Current pinned google_fonts version: $old_version"

# Restore the pinned constraint on any exit (success, failure, or interrupt).
restore_pin() {
  local v="${1:-$old_version}"
  # Replace the line in-place, preserving leading indentation.
  awk -v v="$v" '
    /^[[:space:]]*google_fonts:[[:space:]]*\^?[0-9]/ {
      match($0, /^[[:space:]]*/)
      indent = substr($0, 1, RLENGTH)
      print indent "google_fonts: " v
      next
    }
    { print }
  ' "$pubspec" > "$pubspec.tmp" && mv "$pubspec.tmp" "$pubspec"
}
trap 'restore_pin "$old_version"' ERR INT

# 1. Relax to ^old_version so pub can pick a newer compatible release.
echo "Relaxing constraint to ^$old_version and upgrading…"
restore_pin "^$old_version"
flutter pub upgrade google_fonts >/dev/null

# 2. Read whatever version pub resolved into pubspec.lock.
new_version="$(awk '/^  google_fonts:/{f=1; next} f && /^    version:/{gsub(/"/,"",$2); print $2; exit}' pubspec.lock)"
if [[ -z "${new_version:-}" ]]; then
  echo "Could not determine resolved google_fonts version from pubspec.lock" >&2
  restore_pin "$old_version"
  exit 1
fi

# 3. Re-pin pubspec.yaml to whatever pub resolved (new or unchanged).
restore_pin "$new_version"
trap - ERR INT

if [[ "$new_version" == "$old_version" ]]; then
  echo "Already up to date (google_fonts $old_version).  No asset changes."
  exit 0
fi
echo "Upgrading google_fonts: $old_version -> $new_version"

# 4. Locate the new package source in the pub cache.
pkg_dir="$HOME/.pub-cache/hosted/pub.dev/google_fonts-$new_version"
if [[ ! -d "$pkg_dir" ]]; then
  echo "google_fonts package not found at $pkg_dir" >&2
  exit 1
fi
roboto_src="$pkg_dir/lib/src/google_fonts_parts/part_r.dart"

# 5. Extract Roboto hashes for the four weights we bundle.
# The Roboto block lists weights in the order w100..w900 (normal style first,
# then italics).  Indices 2,3,4,6 = w300,w400,w500,w700 normal.
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

# 6. Download each .ttf into the new versioned asset directory.
out_dir="assets/google_fonts/$new_version"
mkdir -p "$out_dir"
for weight in Light Regular Medium Bold; do
  hash="${weights[$weight]}"
  url="https://fonts.gstatic.com/s/a/$hash.ttf"
  dest="$out_dir/Roboto-$weight.ttf"
  echo "  -> $dest  ($hash)"
  curl -fsSL "$url" -o "$dest"
done

# 7. Update the asset path in pubspec.yaml.
awk -v v="$new_version" '
  /^[[:space:]]*-[[:space:]]*assets\/google_fonts\// {
    match($0, /^[[:space:]]*/)
    indent = substr($0, 1, RLENGTH)
    print indent "- assets/google_fonts/" v "/"
    next
  }
  { print }
' "$pubspec" > "$pubspec.tmp" && mv "$pubspec.tmp" "$pubspec"

# 8. Delete the old asset directory.
old_dir="assets/google_fonts/$old_version"
if [[ -d "$old_dir" ]]; then
  echo "Removing old asset directory: $old_dir"
  rm -rf "$old_dir"
fi

echo
echo "Done.  google_fonts is now pinned to $new_version with matching font assets."
echo "Review the diff and commit:"
echo "  git status"
echo "  git diff $pubspec"
