#!/usr/bin/env bash
#
# Builds the native mkxp-z shared library for Android and gathers it (plus its
# runtime dependencies) into app/src/main/jniLibs/ so Gradle can package the
# APK. The Meson cross-compile step is the same one documented in README.md.
#
# Requirements:
#   - ANDROID_NDK_HOME pointing at your Android NDK
#   - Meson + Ninja installed on the host
#   - CMake, autoconf/automake/libtool, pkg-config (for the dependencies)
#
# Usage:
#   ABIS="arm64-v8a armeabi-v7a x86_64" ./build.sh
#
# The script is idempotent: it skips ABIs whose libraries are already built.

set -euo pipefail

ANDROID_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$ANDROID_DIR/.." && pwd)"
DEPS_DIR="$ANDROID_DIR/deps"
JNILIBS="$ANDROID_DIR/app/src/main/jniLibs"

ABIS="${ABIS:-arm64-v8a armeabi-v7a x86_64}"

: "${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME to your Android NDK directory}"

# Shared libraries that mkxp-z (and SDL) need at runtime. SDLActivity only
# explicitly loads the top-level ones (see its getLibraries()); the rest are
# pulled in automatically by the dynamic linker as DT_NEEDED dependencies, but
# all of them must still be present in the APK's nativeLibraryDir.
LIBS=(
    "libSDL2.so"
    "libSDL2_image.so"
    "libSDL2_ttf.so"
    "libSDL2_sound.so"
    "libopenal.so"
    "libruby.so"
    "libogg.so"
    "libvorbis.so"
    "libvorbisfile.so"
    "libtheoradec.so"
    "libpng.so"
    "libpixman-1.so"
    "libphysfs.so"
    "libfreetype.so"
    "libuchardet.so"
    "libiconv.so"
    "libssl.so"
    "libcrypto.so"
)

# Download the dependency sources the first time around.
if [[ ! -d "$DEPS_DIR/SDL2" || ! -d "$DEPS_DIR/ruby" ]]; then
    echo "Downloading dependency sources..."
    (cd "$DEPS_DIR" && ./get_deps.sh)
fi

# Ruby's build needs a Ruby that runs on this machine. Find it now: once an ABI
# is built, its deps/build-<abi>/bin holds a cross-compiled `ruby` that can't.
export BASERUBY="${BASERUBY:-$(command -v ruby || true)}"
[[ -n "$BASERUBY" ]] || { echo "build.sh: an installed (host) Ruby is required to build Ruby for Android." >&2; exit 1; }

# vars.sh prepends deps/build-<abi>/bin to PATH; start every ABI from the
# original PATH so one ABI's binaries never shadow host tools for the next.
ORIG_PATH="$PATH"

for ABI in $ABIS; do
    PATH="$ORIG_PATH"
    echo "=================================================================="
    echo "Building ABI: $ABI"
    echo "=================================================================="

    export ABI
    # shellcheck disable=SC1091
    source "$DEPS_DIR/vars.sh"

    echo "-- Cross-compiling dependencies (this can take a while)"
    (cd "$DEPS_DIR" && make ABI="$ABI")

    BUILD="$ANDROID_DIR/build-$ABI"

    # build.ninja only exists after a *successful* meson setup. A failed setup
    # (e.g. a missing dependency) leaves a partial directory behind, which
    # would make a later `meson compile` fail with "not a meson build
    # directory" -- so wipe it and re-run setup in that case.
    if [[ ! -f "$BUILD/build.ninja" ]]; then
        echo "-- Configuring Meson ($ABI)"
        rm -rf "$BUILD"
        (cd "$REPO_ROOT" && \
            source "$DEPS_DIR/vars.sh" && \
            meson setup "$BUILD" --cross-file "android/meson-$ABI.txt")
    fi

    echo "-- Building libmkxp-z.so ($ABI)"
    (cd "$REPO_ROOT" && \
        source "$DEPS_DIR/vars.sh" && \
        meson compile -C "$BUILD")

    echo "-- Staging libraries into jniLibs"
    DEST="$JNILIBS/$ABI"
    mkdir -p "$DEST"
    cp -f "$BUILD/libmkxp-z.so" "$DEST/"
    for lib in "${LIBS[@]}"; do
        cp -f "$DEPS_DIR/build-$ABI/lib/$lib" "$DEST/"
    done

    # The NDK's shared C++ runtime. libmkxp-z.so is linked against it (see its
    # DT_NEEDED entries), and unlike the libc/libm/libdl system libraries it is
    # *not* provided by Android, so it must be bundled in the APK.
    case "$ABI" in
        arm64-v8a)   TRIPLE="aarch64-linux-android" ;;
        armeabi-v7a) TRIPLE="arm-linux-androideabi" ;;
        x86_64)      TRIPLE="x86_64-linux-android" ;;
        x86)         TRIPLE="i686-linux-android" ;;
        *)           echo "Unknown ABI: $ABI" >&2; exit 1 ;;
    esac
    LIBCXX_SHARED="$TOOLCHAIN/sysroot/usr/lib/$TRIPLE/libc++_shared.so"
    if [[ -f "$LIBCXX_SHARED" ]]; then
        cp -f "$LIBCXX_SHARED" "$DEST/"
    else
        echo "Warning: libc++_shared.so not found at $LIBCXX_SHARED" >&2
    fi

    echo "=================================================================="
    echo "$ABI done -> $DEST"
    echo "=================================================================="
done

echo "Native libraries are ready under $JNILIBS. Now run:"
echo "  cd $ANDROID_DIR && ./gradlew assembleDebug   (or assembleRelease)"
