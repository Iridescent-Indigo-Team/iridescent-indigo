#!/usr/bin/env bash
#===============================================================================
# install_assets.sh [--force] [SOURCE]
#-------------------------------------------------------------------------------
# Copies the assets of a Pokémon Essentials release into src/assets/:
#   Graphics/            -> src/assets/graphics/   (original 2x size; `make`
#                                                   halves them into build/)
#   Audio/               -> src/assets/audio/
#   soundfont.sf2        -> src/assets/audio/soundfont.sf2
#   PBS/*.txt            -> src/assets/pbs/
#   Data/*.rxdata        -> src/assets/data/       (maps, tilesets, system...)
#
# SOURCE is anything extract_assets.sh accepts (default: lib/pokemon-essentials).
#
# Every installed file is recorded with its checksum in
# src/assets/.installed_manifest. Running the script again updates installed
# files, but never overwrites a file you have changed or added yourself unless
# --force is given. uninstall_assets.sh removes exactly what was installed.
#
# Installed files are also listed in .git/info/exclude so the thousands of
# Essentials files are not committed by accident. To commit an installed file
# you edited, use `git add -f`.
#===============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ASSETS="$ROOT/src/assets"
MANIFEST="$ASSETS/.installed_manifest"
FORCE=0
SOURCE=""

for arg in "$@"; do
  case "$arg" in
    -f|--force) FORCE=1 ;;
    -h|--help) sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) SOURCE="$arg" ;;
  esac
done

ESSENTIALS="$("$ROOT/tools/scripts/extract_assets.sh" ${SOURCE:+"$SOURCE"})"
echo "Installing assets from $ESSENTIALS"

# Previously installed files: relative path -> checksum.
declare -A INSTALLED=()
if [[ -f "$MANIFEST" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    INSTALLED["${line:42}"]="${line:0:40}"
  done < "$MANIFEST"
fi

# Lists "source<TAB>destination-relative-to-src/assets" pairs to install.
list_files() {
  local from="$1" to="$2" filter="${3:-}"
  [[ -d "$ESSENTIALS/$from" ]] || return 0
  (cd "$ESSENTIALS/$from" && find . ${filter:+-maxdepth 1} -type f ${filter:+-name "$filter"} -print) |
    sed 's|^\./||' | grep -v -i -e '\(^\|/\)desktop\.ini$' -e '\(^\|/\)thumbs\.db$' -e '\(^\|/\)\.ds_store$' |
    LC_ALL=C sort |
    while IFS= read -r rel; do
      printf '%s\t%s\n' "$ESSENTIALS/$from/$rel" "$to/$rel"
    done
}

copied=0; updated=0; skipped=0; unchanged=0
NEW_ENTRIES=()   # files whose checksum is (re)computed after copying
KEEP_LINES=()    # skipped files: keep the checksum from the original install
while IFS=$'\t' read -r src rel; do
  dst="$ASSETS/$rel"
  if [[ -e "$dst" ]]; then
    if cmp -s "$src" "$dst"; then
      unchanged=$((unchanged + 1))
      # Keep ownership as it was: only files we installed stay in the manifest.
      [[ -n "${INSTALLED[$rel]:-}" ]] && NEW_ENTRIES+=("$rel")
      continue
    fi
    current="$(sha1sum "$dst" | cut -c1-40)"
    if [[ $FORCE -eq 0 && "${INSTALLED[$rel]:-}" != "$current" ]]; then
      skipped=$((skipped + 1))
      echo "  skip (modified or not installed by this script): $rel"
      [[ -n "${INSTALLED[$rel]:-}" ]] && KEEP_LINES+=("${INSTALLED[$rel]}  $rel")
      continue
    fi
    updated=$((updated + 1))
  else
    copied=$((copied + 1))
  fi
  mkdir -p "$(dirname "$dst")"
  cp -p "$src" "$dst"
  NEW_ENTRIES+=("$rel")
done < <(
  list_files Graphics graphics
  list_files Audio audio
  list_files PBS pbs "*.txt"
  list_files Data data "*.rxdata" | grep -v -e '/Scripts\.rxdata$' -e '/PluginScripts\.rxdata$'
  [[ -f "$ESSENTIALS/soundfont.sf2" ]] && printf '%s\t%s\n' "$ESSENTIALS/soundfont.sf2" "audio/soundfont.sf2"
)

# Rewrite the manifest: fresh checksums for installed files, the original
# checksums for files the user modified (so they still count as modified).
(
  cd "$ASSETS"
  if [[ ${#NEW_ENTRIES[@]} -gt 0 ]]; then
    printf '%s\0' "${NEW_ENTRIES[@]}" | xargs -0 sha1sum
  fi
  if [[ ${#KEEP_LINES[@]} -gt 0 ]]; then
    printf '%s\n' "${KEEP_LINES[@]}"
  fi
) | LC_ALL=C sort -k2 -u > "$MANIFEST.tmp"
mv "$MANIFEST.tmp" "$MANIFEST"

# Keep installed files out of git (local to this clone).
"$ROOT/tools/scripts/uninstall_assets.sh" --update-exclude

echo "Assets: $copied new, $updated updated, $unchanged unchanged, $skipped skipped" \
     "($(wc -l < "$MANIFEST") files tracked in ${MANIFEST#"$ROOT/"})"
[[ $skipped -gt 0 ]] && echo "Use --force to overwrite skipped files."
exit 0
