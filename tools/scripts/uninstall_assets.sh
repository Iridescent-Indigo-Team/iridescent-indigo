#!/usr/bin/env bash
#===============================================================================
# uninstall_assets.sh [--force]
#-------------------------------------------------------------------------------
# Removes the Essentials assets that install_assets.sh copied into src/assets/.
# Only files listed in src/assets/.installed_manifest are touched. Files you
# changed after installing them are kept unless --force is given; files you
# added yourself are never removed. Empty folders are cleaned up, but .gitkeep
# files stay.
#
# --update-exclude only refreshes the list of installed files in
# .git/info/exclude (used by install_assets.sh).
#===============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ASSETS="$ROOT/src/assets"
MANIFEST="$ASSETS/.installed_manifest"
BEGIN_MARK="# >>> pokessentials installed assets (managed by tools/scripts) >>>"
END_MARK="# <<< pokessentials installed assets <<<"
FORCE=0
ONLY_EXCLUDE=0

for arg in "$@"; do
  case "$arg" in
    -f|--force) FORCE=1 ;;
    --update-exclude) ONLY_EXCLUDE=1 ;;
    -h|--help) sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "uninstall_assets: unknown argument $arg" >&2; exit 1 ;;
  esac
done

# Rewrites the managed block of .git/info/exclude from the manifest.
update_exclude() {
  local git_dir exclude
  git_dir="$(git -C "$ROOT" rev-parse --git-dir 2>/dev/null)" || return 0
  [[ "$git_dir" = /* ]] || git_dir="$ROOT/$git_dir"
  exclude="$git_dir/info/exclude"
  mkdir -p "$(dirname "$exclude")"
  touch "$exclude"
  {
    awk -v b="$BEGIN_MARK" -v e="$END_MARK" '$0 == b { skip = 1 } !skip { print } $0 == e { skip = 0 }' "$exclude"
    if [[ -s "$MANIFEST" ]]; then
      echo "$BEGIN_MARK"
      cut -c43- "$MANIFEST" | sed -e 's/[][*?!#\\]/\\&/g' -e 's|^|/src/assets/|'
      echo "$END_MARK"
    fi
  } > "$exclude.tmp"
  mv "$exclude.tmp" "$exclude"
}

if [[ $ONLY_EXCLUDE -eq 1 ]]; then
  update_exclude
  exit 0
fi

if [[ ! -s "$MANIFEST" ]]; then
  echo "No installed assets found (${MANIFEST#"$ROOT/"} is missing or empty)."
  update_exclude
  exit 0
fi

removed=0; kept=0
: > "$MANIFEST.tmp"
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  sum="${line:0:40}"
  rel="${line:42}"
  file="$ASSETS/$rel"
  [[ -e "$file" ]] || continue
  if [[ $FORCE -eq 0 && "$(sha1sum "$file" | cut -c1-40)" != "$sum" ]]; then
    echo "  keep (modified): $rel"
    echo "$line" >> "$MANIFEST.tmp"
    kept=$((kept + 1))
    continue
  fi
  rm -f "$file"
  removed=$((removed + 1))
done < "$MANIFEST"

if [[ -s "$MANIFEST.tmp" ]]; then
  mv "$MANIFEST.tmp" "$MANIFEST"
else
  # Nothing installed is left: forget the scale and the resize report too.
  rm -f "$MANIFEST.tmp" "$MANIFEST" "$ASSETS/.asset_scale" "$ASSETS/.resize_report.txt"
fi

# Remove folders left empty (never the top-level asset folders themselves).
for top in graphics audio pbs data; do
  [[ -d "$ASSETS/$top" ]] && find "$ASSETS/$top" -mindepth 1 -type d -empty -delete
done

update_exclude
echo "Assets: $removed removed, $kept kept."
[[ $kept -gt 0 ]] && echo "Use --force to remove modified files too."
exit 0
