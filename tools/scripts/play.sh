#!/usr/bin/env bash
#===============================================================================
# play.sh - launcher included in the packaged Linux build (make desktop).
# Runs the bundled mkxp-z engine on the game folder this script is in.
# Pass "debug" to start in debug mode.
#===============================================================================
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SRCDIR="$HERE"
export LD_LIBRARY_PATH="$HERE/engine/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
cd "$HERE" && exec "$HERE/engine/mkxp-z" "$@"
