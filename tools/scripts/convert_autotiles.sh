#!/bin/sh
#===============================================================================
# convert_autotiles.sh [--all] [NAME...]
#-------------------------------------------------------------------------------
# Converts RPG Maker XP autotiles (src/assets/graphics/Autotiles/<NAME>.png)
# into Tiled tilesets in src/tiled/tilesets/autotiles: the 48 variants of each
# animation frame, a terrain set for Tiled's terrain brush, and animation.
# Without names, the autotiles converted before are refreshed; --all converts
# every autotile. Same as `make tiled-assets`. See docs/TILED.md#autotiles.
#===============================================================================
cd "$(dirname "$0")/../.." || exit 1
exec "${PYTHON:-python3}" -I tools/importer/tiled/tiled_compiler.py autotiles "$@"
