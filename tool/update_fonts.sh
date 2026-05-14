#!/usr/bin/env bash
# Upgrade all locally-bundled fonts in lock-step with their upstream sources.
#
# This script is the single entry point for refreshing every font that
# ships with the app.  Currently it manages two font families:
#
#   1. google_fonts (Roboto)  — the package + its per-weight .ttf files,
#      checked against pub.dev.  google_fonts is pinned to an exact
#      version (no caret) and runs with allowRuntimeFetching=false, so the
#      bundled .ttf files under assets/google_fonts/<version>/ MUST match
#      the package version exactly (each release embeds its own fresh
#      hashes into URLs of the form https://fonts.gstatic.com/s/a/<hash>.ttf).
#
#   2. DejaVu Sans            — the suit-glyph font, checked against the
#      upstream GitHub release (dejavu-fonts/dejavu-fonts).  The .ttf
#      lives under assets/dejavu/<version>/DejaVuSans.ttf and is
#      referenced from the flutter.fonts: block in pubspec.yaml as well as
#      from tool/generate_icons.sh' fontconfig sandbox (which discovers
#      the versioned dir from pubspec).
#
# Each updater is independent: if one font is already up to date the
# other can still bump.  All pubspec edits preserve indentation and
# comment placement.
#
# Usage: ./tool/update_fonts.sh

set -euo pipefail

cd "$(dirname -- "$(readlink -f -- "$0")")/.."

pubspec="pubspec.yaml"

# ---------------------------------------------------------------------------
# google_fonts (Roboto)
# ---------------------------------------------------------------------------

update_google_fonts() {
  echo "=========================================================="
  echo " google_fonts (Roboto)"
  echo "=========================================================="

  # Read the currently-pinned version from pubspec.yaml.  Accepts either
  # a pinned version (`google_fonts: 8.1.0`) or a caret constraint
  # (`google_fonts: ^8.1.0`) — the caret form is what we briefly write
  # below.
  read_pin() {
    awk '
      /^[[:space:]]*google_fonts:[[:space:]]*\^?[0-9]/ {
        v = $2
        sub(/^\^/, "", v)
        print v
        exit
      }
    ' "$pubspec"
  }

  local old_version
  old_version="$(read_pin)"
  if [[ -z "${old_version:-}" ]]; then
    echo "Could not find a 'google_fonts: <version>' line in $pubspec" >&2
    return 1
  fi
  echo "Current pinned google_fonts version: $old_version"

  # Restore the pinned constraint on any exit (success, failure, interrupt).
  restore_pin() {
    local v="${1:-$old_version}"
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
  local new_version
  new_version="$(awk '/^  google_fonts:/{f=1; next} f && /^    version:/{gsub(/"/,"",$2); print $2; exit}' pubspec.lock)"
  if [[ -z "${new_version:-}" ]]; then
    echo "Could not determine resolved google_fonts version from pubspec.lock" >&2
    restore_pin "$old_version"
    return 1
  fi

  # 3. Re-pin pubspec.yaml to whatever pub resolved (new or unchanged).
  restore_pin "$new_version"
  trap - ERR INT

  if [[ "$new_version" == "$old_version" ]]; then
    echo "Already up to date (google_fonts $old_version).  No asset changes."
    return 0
  fi
  echo "Upgrading google_fonts: $old_version -> $new_version"

  # 4. Locate the new package source in the pub cache.
  local pkg_dir="$HOME/.pub-cache/hosted/pub.dev/google_fonts-$new_version"
  if [[ ! -d "$pkg_dir" ]]; then
    echo "google_fonts package not found at $pkg_dir" >&2
    return 1
  fi
  local roboto_src="$pkg_dir/lib/src/google_fonts_parts/part_r.dart"

  # 5. Extract Roboto hashes for the four weights we bundle.
  # The Roboto block lists weights in the order w100..w900 (normal style
  # first, then italics).  Indices 2,3,4,6 = w300,w400,w500,w700 normal.
  local hashes
  mapfile -t hashes < <(
    awk "/^  static TextStyle roboto\\(/,/fontFamily: 'Roboto',/" "$roboto_src" \
      | grep -oE "'[0-9a-f]{64}'" \
      | tr -d "'"
  )
  if (( ${#hashes[@]} < 9 )); then
    echo "Failed to parse Roboto hashes from $roboto_src" >&2
    return 1
  fi
  declare -A weights=(
    [Light]="${hashes[2]}"    # w300
    [Regular]="${hashes[3]}"  # w400
    [Medium]="${hashes[4]}"   # w500
    [Bold]="${hashes[6]}"     # w700
  )

  # 6. Download each .ttf into the new versioned asset directory.
  local out_dir="assets/google_fonts/$new_version"
  mkdir -p "$out_dir"
  local weight hash url dest
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
  local old_dir="assets/google_fonts/$old_version"
  if [[ -d "$old_dir" ]]; then
    echo "Removing old asset directory: $old_dir"
    rm -rf "$old_dir"
  fi

  echo "google_fonts is now pinned to $new_version with matching assets."
}

# ---------------------------------------------------------------------------
# DejaVu Sans
# ---------------------------------------------------------------------------

update_dejavu() {
  echo
  echo "=========================================================="
  echo " DejaVu Sans"
  echo "=========================================================="

  # Single source of truth for the version: the asset path under
  # flutter.fonts in pubspec.yaml.  Strip YAML comments first so a
  # documentation comment like `assets/dejavu/<version>/` can't match.
  local old_version
  old_version="$(sed 's/#.*//' "$pubspec" \
    | grep -oE 'assets/dejavu/[^/[:space:]]+' \
    | head -1 | sed 's:.*/::')"
  if [[ -z "${old_version:-}" ]]; then
    echo "Could not find an 'assets/dejavu/<version>/' path in $pubspec" >&2
    return 1
  fi
  echo "Current bundled DejaVu version: $old_version"

  # Query upstream GitHub releases for the latest tag.  Tags are of the
  # form `version_2_37`; convert to dotted version `2.37`.
  local api="https://api.github.com/repos/dejavu-fonts/dejavu-fonts/releases/latest"
  local tag new_version
  tag="$(curl -fsSL "$api" \
    | grep -oE '"tag_name":[[:space:]]*"[^"]+"' \
    | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
  if [[ -z "${tag:-}" ]]; then
    echo "Could not determine latest DejaVu release from $api" >&2
    return 1
  fi
  new_version="${tag#version_}"
  new_version="${new_version//_/.}"
  echo "Latest upstream DejaVu version: $new_version"

  if [[ "$new_version" == "$old_version" ]]; then
    echo "Already up to date (DejaVu $old_version).  No asset changes."
    return 0
  fi
  echo "Upgrading DejaVu: $old_version -> $new_version"

  if ! command -v unzip >/dev/null 2>&1; then
    echo "error: unzip not found (install with: sudo apt install unzip)" >&2
    return 1
  fi

  # Download the smallest tarball that contains DejaVuSans.ttf.  The
  # `dejavu-sans-ttf-<v>.zip` archive only ships the Sans family.
  local url="https://github.com/dejavu-fonts/dejavu-fonts/releases/download/$tag/dejavu-sans-ttf-$new_version.zip"
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN INT
  echo "Downloading $url"
  curl -fsSL "$url" -o "$tmpdir/dejavu.zip"
  (cd "$tmpdir" && unzip -q dejavu.zip)

  # Locate DejaVuSans.ttf in the extracted tree (path includes a top-level
  # versioned dir like `dejavu-sans-ttf-2.38/ttf/DejaVuSans.ttf`).
  local ttf_matches
  mapfile -t ttf_matches < <(find "$tmpdir" -type f -name DejaVuSans.ttf)
  if (( ${#ttf_matches[@]} != 1 )); then
    echo "error: expected exactly 1 DejaVuSans.ttf in upstream zip, found ${#ttf_matches[@]}" >&2
    printf '  %s\n' "${ttf_matches[@]}" >&2
    return 1
  fi
  local src="${ttf_matches[0]}"

  # Place into the new versioned dir along with the LICENSE shipped
  # inside the same release zip (so a future upstream amendment to the
  # license text gets picked up automatically). The upstream zip ships
  # a single top-level `LICENSE` file; we keep the same name to avoid a
  # rename step.
  local out_dir="assets/dejavu/$new_version"
  mkdir -p "$out_dir"
  cp "$src" "$out_dir/DejaVuSans.ttf"
  local lic_matches
  mapfile -t lic_matches < <(find "$tmpdir" -type f -name LICENSE)
  if (( ${#lic_matches[@]} != 1 )); then
    echo "error: expected exactly 1 LICENSE file in upstream zip, found ${#lic_matches[@]}" >&2
    printf '  %s\n' "${lic_matches[@]}" >&2
    return 1
  fi
  cp "${lic_matches[0]}" "$out_dir/LICENSE"
  echo "  -> $out_dir/LICENSE  (from upstream zip)"
  echo "  -> $out_dir/DejaVuSans.ttf"

  # Rewrite every assets/dejavu/<old>/ reference in tracked text files
  # (pubspec.yaml plus any source that hardcodes the versioned path,
  # e.g. the LicenseRegistry.addLicense call in lib/main.dart). Auto-
  # discover via `git grep` so a new caller is picked up without
  # touching this script. Exclude assets/ to avoid rewriting binary
  # font files that happen to embed the old path string.
  local sweep_files=()
  if command -v git >/dev/null 2>&1; then
    mapfile -t sweep_files < <(
      git grep -lE "assets/dejavu/${old_version}/" -- ':(exclude)assets/' \
        || true
    )
  fi
  local f
  for f in "${sweep_files[@]}"; do
    [[ -f "$f" ]] || continue
    awk -v ov="$old_version" -v nv="$new_version" '
      {
        gsub("assets/dejavu/" ov "/", "assets/dejavu/" nv "/")
        print
      }
    ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  done

  local old_dir="assets/dejavu/$old_version"
  if [[ -d "$old_dir" ]]; then
    echo "Removing old asset directory: $old_dir"
    rm -rf "$old_dir"
  fi

  echo "DejaVu Sans is now bundled at version $new_version."
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

update_google_fonts
update_dejavu

echo
echo "Done.  Review the diff and commit:"
echo "  git status"
echo "  git diff $pubspec"
