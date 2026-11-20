#!/bin/sh
#===============================================================================
# tiled.sh [TILED_ARGS...]
#-------------------------------------------------------------------------------
# Opens the Pokessentials Tiled project (src/tiled/pokessentials.tiled-project)
# in Tiled, after making sure the generated files Tiled needs are there:
#   * the project's custom types (map metadata, encounters, event pages...),
#   * converted autotiles and event previews (if the graphics are installed).
# Set TILED to the Tiled program if it isn't on your PATH, e.g.
#   TILED=/Applications/Tiled.app/Contents/MacOS/Tiled ./tiled.sh
# Tiled 1.10 or newer is needed. See docs/TILED.md.
#===============================================================================
set -e
cd "$(dirname "$0")"
PYTHON="${PYTHON:-python3}"
TOOL="tools/importer/tiled/tiled_compiler.py"
PROJECT="src/tiled/pokessentials.tiled-project"

"$PYTHON" -I "$TOOL" project >/dev/null
if [ -d src/assets/graphics/Characters ] && [ ! -f src/tiled/generated/characters.tsj ]; then
    "$PYTHON" -I "$TOOL" previews || echo "Event previews weren't made (is Pillow installed?)." >&2
fi

TILED="${TILED:-}"
if [ -z "$TILED" ]; then
    for candidate in tiled Tiled /Applications/Tiled.app/Contents/MacOS/Tiled; do
        if command -v "$candidate" >/dev/null 2>&1 || [ -x "$candidate" ]; then
            TILED="$candidate"
            break
        fi
    done
fi
if [ -z "$TILED" ]; then
    echo "Tiled wasn't found. Install it from https://www.mapeditor.org (1.10 or newer)," >&2
    echo "or set TILED to its program, then run ./tiled.sh again." >&2
    exit 1
fi
exec "$TILED" --project "$PROJECT" "$@"
