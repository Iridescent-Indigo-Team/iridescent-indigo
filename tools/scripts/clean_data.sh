#!/usr/bin/env bash
#===============================================================================
# clean_data.sh [--all]
#-------------------------------------------------------------------------------
# Removes generated game data so it is rebuilt on the next `make`/launch:
#   * build/Data/*.dat        compiled PBS data (recompiled by `make compile`
#                             or the first ./game.sh launch in debug mode)
#   * build/Data/PluginScripts.rxdata
#   * build/.essentials       extracted Essentials zip (extract_assets.sh)
#
# --all removes the whole build/ folder instead (including a built engine).
#===============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD="$ROOT/build"

case "${1:-}" in
  --all)
    rm -rf "$BUILD"
    echo "Removed build/."
    ;;
  "")
    rm -f "$BUILD"/Data/*.dat "$BUILD/Data/PluginScripts.rxdata"
    rm -rf "$BUILD/.essentials"
    echo "Removed compiled data from build/Data and the extracted Essentials staging folder."
    ;;
  -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
  *) echo "clean_data: unknown argument $1" >&2; exit 1 ;;
esac
