#!/usr/bin/env bash
# Update dependencies the way `npm update --save` does:
#   1. Run `flutter pub upgrade` (respects existing semver ranges — no major
#      version bumps).
#   2. For every direct/dev dependency in pubspec.yaml whose constraint uses
#      a caret (`^X.Y.Z`), rewrite the caret constraint to point at the
#      currently-resolved version from pubspec.lock.
#
# Constraints WITHOUT a caret (e.g. `google_fonts: 8.1.0`) are intentional
# pins and are left untouched.  SDK-style entries (`sdk: flutter`) are
# skipped automatically.
#
# This is the manifest-rewriting half that `flutter pub upgrade` deliberately
# omits — pub only edits pubspec.yaml on `--major-versions` upgrades.
#
# Usage: ./tool/update_deps.sh

set -euo pipefail

cd "$(dirname "$0")/.."

pubspec="pubspec.yaml"
lockfile="pubspec.lock"

if [[ ! -f "$pubspec" || ! -f "$lockfile" ]]; then
  echo "Run this from a directory containing pubspec.yaml + pubspec.lock" >&2
  exit 1
fi

echo "==> flutter pub upgrade (within existing constraints)"
flutter pub upgrade

# Build "name<TAB>version" map of every package in pubspec.lock.
echo "==> Aligning caret constraints in $pubspec to resolved versions"
resolved_map="$(awk '
  /^packages:/ { in_packages = 1; next }
  in_packages && /^  [a-zA-Z0-9_]+:/ {
    name = $1
    sub(/:$/, "", name)
    next
  }
  in_packages && /^    version:/ {
    v = $2
    gsub(/"/, "", v)
    print name "\t" v
  }
' "$lockfile")"

changes=0
while IFS=$'\t' read -r name resolved; do
  [[ -z "$name" ]] && continue
  # Look for `  <name>: ^X.Y.Z` (two-space indent, caret constraint).
  # Anchored at column 1 so flutter_launcher_icons config keys aren't matched.
  current_line="$(grep -E "^  ${name}: \\^[0-9]" "$pubspec" || true)"
  [[ -z "$current_line" ]] && continue
  current_constraint="$(printf '%s' "$current_line" | sed -E 's/^  [^:]+: //')"
  new_constraint="^${resolved}"
  if [[ "$current_constraint" == "$new_constraint" ]]; then
    continue
  fi
  echo "  $name: $current_constraint -> $new_constraint"
  # Use a different sed delimiter and escape only what's needed.
  sed -i -E "s|^(  ${name}: )\\^[0-9][^[:space:]]*|\\1${new_constraint}|" \
    "$pubspec"
  changes=$((changes + 1))
done <<< "$resolved_map"

if (( changes == 0 )); then
  echo "==> No constraint changes — pubspec.yaml already matches lock file."
else
  echo "==> Rewrote $changes constraint(s).  Re-resolving to confirm…"
  flutter pub get >/dev/null
  echo "==> Done.  Review with: git diff pubspec.yaml pubspec.lock"
fi
