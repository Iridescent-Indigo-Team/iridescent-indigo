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
# automake, libtool, bison, nasm, ruby (an installed Ruby is needed to build
# mkxp-z's own Ruby 3.1), plus the X11/OpenGL/ALSA/PulseAudio development
# headers. See docs/BUILDING.md for the package list.
#
# Set SKIP_DEPS=1 to skip step 1 when the dependencies are already built.
# Dependencies are cloned shallowly (--depth 1) and the dependency build is
# retried DEPS_RETRIES times (default 3) to ride out dropped connections;
# re-running continues where a failed run stopped. FluidSynth is fetched
# without its ~570 MB test-data submodule.
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
for tool in gcc g++ make cmake meson ninja pkg-config git autoconf automake libtoolize bison ruby; do
  command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if [[ ${#missing[@]} -gt 0 ]]; then
  msg="missing build tools: ${missing[*]} (see docs/BUILDING.md)"
  [[ " ${missing[*]} " == *" ruby "* ]] &&
    msg+=$'\n'"  An installed Ruby is required: building mkxp-z's Ruby 3.1 from source needs a host Ruby (e.g. sudo apt install ruby)."
  die "$msg"
fi
BASERUBY="$(command -v ruby)"

# Earlier versions of this script ran the dependency build from the wrong
# folder, leaving these behind at the repository root. They are not used.
for stray in "$ROOT/downloads" "$ROOT/build-$ARCH"; do
  [[ -e "$stray" ]] && echo "Note: ${stray#"$ROOT/"}/ is left over from an older build and can be deleted."
done

# FluidSynth is cloned by the dependency Makefile with --recurse-submodules,
# which also downloads its ~570 MB test-data submodule (test/manual) that the
# build never needs. Fetch it here with only the submodule it does need (gcem);
# the Makefile then sees FluidSynth is already downloaded and skips its clone.
prefetch_fluidsynth() {
  local dir="$MKXPZ_SRC/linux/downloads/$ARCH/fluidsynth"
  local tag
  tag="$(grep -o 'FluidSynth/fluidsynth -b [^ ]*' "$MKXPZ_SRC/linux/Makefile" | awk '{print $3}')"
  [[ -n "$tag" ]] || return 0   # Makefile changed; let it clone FluidSynth itself
  # A clone interrupted before checkout leaves a folder git can't clone into.
  if [[ -d "$dir" && ! -f "$dir/CMakeLists.txt" ]]; then
    rm -rf "$dir"
  fi
  if [[ ! -f "$dir/CMakeLists.txt" ]]; then
    echo "Downloading FluidSynth $tag (without its 570 MB test data)..."
    mkdir -p "$(dirname "$dir")"
    git -c advice.detachedHead=false clone -q --depth 1 -b "$tag" \
      https://github.com/FluidSynth/fluidsynth "$dir" || return 1
  fi
  if [[ -z "$(ls -A "$dir/gcem" 2>/dev/null)" ]]; then
    echo "Downloading FluidSynth's gcem submodule..."
    git -C "$dir" submodule update -q --init --depth 1 gcem || return 1
  fi
}

# Step 1: dependencies.
if [[ "${SKIP_DEPS:-0}" != 1 ]]; then
  echo "Building mkxp-z dependencies (lib/mkxp-z/linux)..."
  DEPS_DIR="$MKXPZ_SRC/linux"
  RUBY_SRC="$DEPS_DIR/downloads/$ARCH/ruby"
  # A Ruby source tree configured without a host Ruby fails with "executable
  # host ruby is required"; remove its Makefile so it is configured again.
  if [[ ! -e "$DEPS_DIR/build-$ARCH/lib/libruby.so.3.1" && -f "$RUBY_SRC/Makefile" ]] &&
     ! grep -q -- "--with-baseruby" "$RUBY_SRC/config.status" 2>/dev/null; then
    rm -f "$RUBY_SRC/Makefile"
  fi
  # Abort stalled downloads quickly so they can be retried.
  export GIT_HTTP_LOW_SPEED_LIMIT="${GIT_HTTP_LOW_SPEED_LIMIT:-1000}"
  export GIT_HTTP_LOW_SPEED_TIME="${GIT_HTTP_LOW_SPEED_TIME:-60}"
  RETRIES="${DEPS_RETRIES:-3}"
  attempt=1
  # The dependency Makefile builds its paths from $PWD, so run it from its own
  # folder (make -C would leave PWD pointing at the caller's folder). CLONE
  # makes every git clone shallow: much smaller downloads, same sources.
  # Downloads print nothing while they run, so large ones can take a while.
  echo "Downloads are quiet while they run; large ones can take several minutes."
  until prefetch_fluidsynth &&
        (cd "$DEPS_DIR" && make PWD="$DEPS_DIR" CLONE="git clone -q --depth 1" \
           RUBY_FLAGS="--with-baseruby=$BASERUBY" everything); do
    if (( attempt >= RETRIES )); then
      die "building the dependencies failed $attempt times. If the errors above mention" \
          "\"RPC failed\", \"connection reset\" or \"early EOF\", it is a network problem:" \
          "run 'make mkxp' again and it will continue where it stopped."
    fi
    attempt=$((attempt + 1))
    echo "Dependency build failed; retrying in 5 seconds (attempt $attempt of $RETRIES)..." >&2
    sleep 5
  done
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
