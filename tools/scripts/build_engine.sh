#!/usr/bin/env bash
#===============================================================================
# build_engine.sh [OUT_DIR]
#-------------------------------------------------------------------------------
# Builds the mkxp-z engine from lib/mkxp-z for Linux and installs it into
# OUT_DIR (default: build/engine):
#   OUT_DIR/mkxp-z   the engine executable
#   OUT_DIR/lib/     the shared libraries it needs (Ruby)
#
# Step 1 builds mkxp-z's dependencies from source with lib/mkxp-z/linux/Makefile
# (SDL2, Ruby 3.1, OpenAL, ...). This takes a while the first time; later runs
# reuse lib/mkxp-z/linux/build-<arch>. Step 2 builds mkxp-z with meson.
#
# Requirements: gcc/g++, make, cmake, meson, ninja, pkg-config, git, autoconf,
# automake, libtool, bison, nasm, plus the X11/OpenGL/ALSA/PulseAudio
# development headers. See docs/BUILDING.md for the package list.
#
# Set SKIP_DEPS=1 to skip step 1 when the dependencies are already built.
#===============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${1:-$ROOT/build/engine}"
[[ "$OUT" = /* ]] || OUT="$ROOT/$OUT"
MKXPZ_SRC="$ROOT/lib/mkxp-z"
ARCH="$(uname -m)"
MESON_BUILD="$ROOT/build/.engine-build"

die() { echo "build_engine: $*" >&2; exit 1; }

[[ "$(uname -s)" = Linux ]] || die "only Linux builds are automated; see lib/mkxp-z/README.md for other platforms and set MKXPZ to the result."
missing=()
for tool in gcc g++ make cmake meson ninja pkg-config git autoconf automake libtoolize bison; do
  command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
[[ ${#missing[@]} -eq 0 ]] || die "missing build tools: ${missing[*]} (see docs/BUILDING.md)"

# Step 1: dependencies.
if [[ "${SKIP_DEPS:-0}" != 1 ]]; then
  echo "Building mkxp-z dependencies (lib/mkxp-z/linux)..."
  make -C "$MKXPZ_SRC/linux" everything
fi

# Step 2: mkxp-z itself, against the dependencies built above.
# vars.sh reads variables that may be unset, so relax "set -u" for it.
set +u
# shellcheck disable=SC1091
source "$MKXPZ_SRC/linux/vars.sh"
set -u
if [[ ! -f "$MESON_BUILD/build.ninja" ]]; then
  meson setup "$MESON_BUILD" "$MKXPZ_SRC" --buildtype=release
fi
ninja -C "$MESON_BUILD"

mkdir -p "$OUT/lib"
EXE="$(find "$MESON_BUILD" -maxdepth 1 -type f -name 'mkxp-z*' -perm -u+x | head -n1)"
[[ -n "$EXE" ]] || die "the meson build did not produce an mkxp-z executable."
cp "$EXE" "$OUT/mkxp-z"
# Ship the shared libraries the engine links that came from the dependency
# build (system libraries are expected on the player's machine).
DEPS_LIB="$MKXPZ_PREFIX/lib"
LD_LIBRARY_PATH="$DEPS_LIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ldd "$OUT/mkxp-z" |
  awk '$3 ~ /^\// { print $3 }' |
  while IFS= read -r lib; do
    case "$lib" in "$MKXPZ_PREFIX"/*) cp -L "$lib" "$OUT/lib/" ;; esac
  done
echo "Engine installed to ${OUT#"$ROOT/"}/mkxp-z"
