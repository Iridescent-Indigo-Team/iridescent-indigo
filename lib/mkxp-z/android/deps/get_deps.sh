#!/bin/bash
#
# Downloads / clones the third-party dependencies that mkxp-z needs to build
# for Android. These are cross-compiled by the accompanying Makefile into
# android/deps/build-<abi>/ and later picked up by Meson through pkg-config.
#
# The sources, versions and branches mirror the project's own linux/Makefile
# (the canonical dependency set) adapted where Android needs shared libraries.
#
# Run from android/deps/:
#   ./get_deps.sh
#

set -e

GIT_ARGS="-q -c advice.detachedHead=false --single-branch --depth 1"

# Xiph libogg
if [[ ! -d "libogg" ]]; then
  echo "Downloading libogg..."
  git clone $GIT_ARGS -b v1.3.6 https://github.com/xiph/ogg libogg
fi

# Xiph libvorbis
if [[ ! -d "libvorbis" ]]; then
  echo "Downloading libvorbis..."
  git clone $GIT_ARGS -b v1.3.7 https://github.com/xiph/vorbis libvorbis
fi

# Xiph libtheora
if [[ ! -d "libtheora" ]]; then
  echo "Downloading libtheora..."
  git clone $GIT_ARGS https://github.com/xiph/theora libtheora
fi

# GNU libiconv
if [[ ! -d "libiconv" ]]; then
  echo "Downloading libiconv..."
  wget -q https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.18.tar.gz
  tar -xzf libiconv-1.18.tar.gz
  mv libiconv-1.18 libiconv
  rm -f libiconv-1.18.tar.gz
fi

# uchardet
if [[ ! -d "uchardet" ]]; then
  echo "Downloading uchardet..."
  git clone $GIT_ARGS -b v0.0.8 https://gitlab.freedesktop.org/uchardet/uchardet uchardet
fi

# Pixman
if [[ ! -d "pixman" ]]; then
  echo "Downloading Pixman..."
  git clone $GIT_ARGS -b pixman-0.42.2 https://gitlab.freedesktop.org/pixman/pixman pixman
fi

# PhysicsFS
if [[ ! -d "physfs" ]]; then
  echo "Downloading PhysicsFS..."
  git clone $GIT_ARGS -b release-3.2.0 https://github.com/icculus/physfs physfs
fi

# OpenAL Soft
if [[ ! -d "openal" ]]; then
  echo "Downloading OpenAL Soft..."
  git clone $GIT_ARGS -b 1.24.3 https://github.com/kcat/openal-soft openal
fi

# SDL2 (mkxp-z fork)
if [[ ! -d "SDL2" ]]; then
  echo "Downloading SDL2..."
  git clone $GIT_ARGS -b mkxp-z-2.28.1 https://github.com/mkxp-z/SDL SDL2
fi

# SDL2_image (mkxp-z fork)
if [[ ! -d "SDL2_image" ]]; then
  echo "Downloading SDL2_image..."
  git clone $GIT_ARGS -b mkxp-z https://github.com/mkxp-z/SDL_image SDL2_image
  # Fetch the vendored image codecs (libpng, libjpeg, ...).
  cd SDL2_image
  ./external/download.sh
  cd ..
fi

# SDL2_ttf
if [[ ! -d "SDL2_ttf" ]]; then
  echo "Downloading SDL2_ttf..."
  git clone $GIT_ARGS -b release-2.20.2 https://github.com/libsdl-org/SDL_ttf SDL2_ttf
fi

# SDL2_sound (mkxp-z fork)
if [[ ! -d "SDL2_sound" ]]; then
  echo "Downloading SDL2_sound..."
  git clone $GIT_ARGS -b git https://github.com/mkxp-z/SDL_sound SDL2_sound
fi

# FreeType (mkxp-z fork; used directly by mkxp-z for font rendering)
if [[ ! -d "freetype" ]]; then
  echo "Downloading FreeType..."
  git clone $GIT_ARGS --recurse-submodules https://github.com/mkxp-z/freetype2 freetype
fi

# libpng (used directly by mkxp-z for PNG loading/saving)
if [[ ! -d "libpng" ]]; then
  echo "Downloading libpng..."
  git clone $GIT_ARGS -b v1.6.50 https://github.com/pnggroup/libpng libpng
fi

# OpenSSL
if [[ ! -d "openssl" ]]; then
  echo "Downloading OpenSSL..."
  git clone $GIT_ARGS -b openssl-3.0.12 https://github.com/openssl/openssl openssl
fi

# Ruby (mkxp-z fork)
if [[ ! -d "ruby" ]]; then
  echo "Downloading Ruby..."
  git clone $GIT_ARGS -b mkxp-z-3.1.3 https://github.com/mkxp-z/ruby ruby
fi

echo "Done!"
