# Source this before running Meson for an Android build. It points pkg-config
# and the compiler/linker at the cross-compiled dependency prefix and puts the
# Android NDK's clang wrappers on PATH (which the Meson cross files expect).
#
# Usage (from the android/ directory):
#   source deps/vars.sh
#   meson setup build-arm64-v8a --cross-file meson-arm64-v8a.txt
#   ninja -C build-arm64-v8a

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Android NDK location. Override if not set.
: "${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME to your Android NDK directory}"

# Target ABI (defaults to arm64-v8a). Must match the deps you built and the
# Meson cross file you use.
ABI="${ABI:-arm64-v8a}"

# Host platform triple of the NDK prebuilt tools.
HOST_PLATFORM="${HOST_PLATFORM:-$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)}"
TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$HOST_PLATFORM"

MKXPZ_PREFIX="$DIR/build-${ABI}"

export PATH="$TOOLCHAIN/bin:$DIR/build-${ABI}/bin:$PATH"
export PKG_CONFIG_LIBDIR="$DIR/build-${ABI}/lib/pkgconfig"
export CFLAGS="-I$DIR/build-${ABI}/include"
export CPPFLAGS="-I$DIR/build-${ABI}/include"
export LDFLAGS="-L$DIR/build-${ABI}/lib"

echo "Android deps prefix: $MKXPZ_PREFIX"
echo "NDK toolchain:       $TOOLCHAIN"
