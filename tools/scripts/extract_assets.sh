#!/usr/bin/env bash
#===============================================================================
# extract_assets.sh [SOURCE]
#-------------------------------------------------------------------------------
# Finds a Pokémon Essentials release and prints the folder that contains its
# Graphics/, Audio/, PBS/ and Data/ folders. install_assets.sh calls this.
#
# SOURCE can be:
#   * a folder holding an Essentials release (default: lib/pokemon-essentials)
#   * a .zip of an Essentials release; it is unpacked into build/.essentials
#
# The Essentials folder is found anywhere inside SOURCE, so a zip whose files
# are inside a top-level "Pokemon Essentials v21.1" folder works too.
#===============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE="${1:-$ROOT/lib/pokemon-essentials}"
STAGING="$ROOT/build/.essentials"

die() { echo "extract_assets: $*" >&2; exit 1; }

# Prints the first folder under $1 that looks like an Essentials release.
find_essentials() {
  local dir
  while IFS= read -r -d '' dir; do
    dir="$(dirname "$dir")"
    if [[ -d "$dir/Graphics" && -d "$dir/Audio" && -d "$dir/PBS" && -d "$dir/Data" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
  done < <(find "$1" -maxdepth 3 -type d -name Graphics -print0 | sort -z)
  return 1
}

if [[ -d "$SOURCE" ]]; then
  find_essentials "$SOURCE" || die "$SOURCE does not contain an Essentials release (Graphics/, Audio/, PBS/, Data/)"
  exit 0
fi

[[ -f "$SOURCE" ]] || die "$SOURCE does not exist"
case "$SOURCE" in
  *.zip|*.ZIP) ;;
  *) die "unsupported source $SOURCE (expected a folder or a .zip)" ;;
esac
command -v unzip >/dev/null 2>&1 || die "unzip is required to extract $SOURCE"

# Re-extract only when the archive changed since the last extraction.
STAMP="$STAGING/.source"
if [[ ! -f "$STAMP" || "$(cat "$STAMP")" != "$(realpath "$SOURCE")" || "$SOURCE" -nt "$STAMP" ]]; then
  rm -rf "$STAGING"
  mkdir -p "$STAGING"
  echo "Extracting $SOURCE..." >&2
  unzip -q "$SOURCE" -d "$STAGING"
  realpath "$SOURCE" > "$STAMP"
fi
find_essentials "$STAGING" || die "$SOURCE does not contain an Essentials release"
