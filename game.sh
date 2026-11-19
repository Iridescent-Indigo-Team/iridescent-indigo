#!/usr/bin/env bash
#===============================================================================
# game.sh [options] [-- engine arguments]
#-------------------------------------------------------------------------------
# Builds the game folder (build/) and launches it with mkxp-z.
#
# Options:
#   --release    run without debug mode (no compile prompt, no debug menu)
#   --no-build   skip `make build`
#   --live       load scripts straight from src/data instead of build/Scripts,
#                so script edits need no rebuild
#   --compile    compile PBS data into build/Data/*.dat and exit (headless
#                when there is no display; used by `make compile`)
#   --dump-schema FILE
#                write the PBS schemas of all GameData classes to FILE as JSON
#                and exit (headless like --compile; used by `make pbs-schema`)
#   -h, --help   show this help
#
# The engine is the first one found of:
#   1. $MKXPZ                  (path to an mkxp-z executable)
#   2. build/engine/mkxp-z     (built by `make mkxp`)
#   3. mkxp-z on your PATH
#===============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="${BUILD:-$ROOT/build}"
DEBUG=1
DO_BUILD=1
LIVE=0
COMPILE=0
DUMP_SCHEMA=""
ENGINE_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release) DEBUG=0 ;;
    --no-build) DO_BUILD=0 ;;
    --live) LIVE=1 ;;
    --compile) COMPILE=1 ;;
    --dump-schema)
      [[ $# -ge 2 ]] || { echo "game.sh: --dump-schema needs a file name" >&2; exit 1; }
      DUMP_SCHEMA="$2"; shift ;;
    -h|--help) sed -n '2,23p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --) shift; ENGINE_ARGS+=("$@"); break ;;
    *) ENGINE_ARGS+=("$1") ;;
  esac
  shift
done

die() { echo "game.sh: $*" >&2; exit 1; }

if [[ $DO_BUILD -eq 1 ]]; then
  make -C "$ROOT" --no-print-directory BUILD="$BUILD" build
fi
[[ -f "$BUILD/mkxp.json" ]] || die "$BUILD is not built yet; run 'make' first."

# Find the engine.
ENGINE=""
ENGINE_LIBS=""
if [[ -n "${MKXPZ:-}" ]]; then
  [[ -x "$MKXPZ" ]] || die "MKXPZ=$MKXPZ is not an executable."
  ENGINE="$MKXPZ"
elif [[ -x "$BUILD/engine/mkxp-z" ]]; then
  ENGINE="$BUILD/engine/mkxp-z"
  ENGINE_LIBS="$BUILD/engine/lib"
elif command -v mkxp-z >/dev/null 2>&1; then
  ENGINE="$(command -v mkxp-z)"
else
  die "no mkxp-z engine found. Run 'make mkxp', put mkxp-z on your PATH, or set MKXPZ=/path/to/mkxp-z."
fi

export SRCDIR="$BUILD"   # mkxp-z (Linux) uses this as the game folder
[[ -n "$ENGINE_LIBS" ]] && export LD_LIBRARY_PATH="$ENGINE_LIBS${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
if [[ $LIVE -eq 1 ]]; then
  export POKESSENTIALS_SCRIPTS="$ROOT/src/data"
fi

ARGS=()
[[ $DEBUG -eq 1 || $COMPILE -eq 1 || -n "$DUMP_SCHEMA" ]] && ARGS+=(debug)
ARGS+=(${ENGINE_ARGS[@]+"${ENGINE_ARGS[@]}"})

# Runs the engine without a window when there is no display, waits for it to
# write the marker file $1, and fails if it doesn't.
run_headless() {
  local marker="$BUILD/$1"
  # No sound is needed, and a headless machine may have no audio device.
  export ALSOFT_DRIVERS="${ALSOFT_DRIVERS:-null}"
  rm -f "$marker"
  # Never wait forever: a message box can't be answered in a headless run.
  local timeout_cmd=()
  command -v timeout >/dev/null 2>&1 && timeout_cmd=(timeout "${COMPILE_TIMEOUT:-900}")
  if [[ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] && command -v xvfb-run >/dev/null 2>&1; then
    ${timeout_cmd[@]+"${timeout_cmd[@]}"} xvfb-run -a -s "-screen 0 1024x768x24" "$ENGINE" "${ARGS[@]}" || true
  else
    ${timeout_cmd[@]+"${timeout_cmd[@]}"} "$ENGINE" "${ARGS[@]}" || true
  fi
  [[ -f "$marker" ]] || return 1
  rm -f "$marker"
}

if [[ -n "$DUMP_SCHEMA" ]]; then
  [[ "$DUMP_SCHEMA" = /* ]] || DUMP_SCHEMA="$PWD/$DUMP_SCHEMA"
  mkdir -p "$(dirname "$DUMP_SCHEMA")" "$BUILD/Data"   # Plugins compile into Data/
  cd "$BUILD"
  export POKESSENTIALS_DUMP_SCHEMA="$DUMP_SCHEMA"
  run_headless .dump_ok || die "dumping the PBS schema failed (see the output above)."
  echo "Wrote the PBS schema to $DUMP_SCHEMA."
  exit 0
fi

cd "$BUILD"
if [[ $COMPILE -eq 1 ]]; then
  export POKESSENTIALS_COMPILE_ONLY=1
  run_headless .compile_ok || die "compiling the game data failed (see the output above)."
  echo "Compiled PBS data into $BUILD/Data."
  exit 0
fi
exec "$ENGINE" "${ARGS[@]}"
