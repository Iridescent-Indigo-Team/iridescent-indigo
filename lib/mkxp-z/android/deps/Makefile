# Cross-compiles all of mkxp-z's dependencies for Android and installs them
# into android/deps/build-<abi>/ so that Meson can find them via pkg-config.
#
# This is the Android equivalent of linux/Makefile + linux/target-*.sh, using
# the Android NDK's clang toolchain. Dependencies are built as shared libraries
# so that Meson's default (non-static) dependency resolution links them cleanly
# into libmkxp-z.so without static-library ordering/PIC problems.
#
# Usage (from android/deps/):
#   ./get_deps.sh                 # download the dependency sources
#   make ABI=arm64-v8a            # cross-compile everything
#
# Set ANDROID_NDK_HOME (or ANDROID_NDK) to your NDK root. The default API level
# is 21 (Android 5.0).

NDK := $(or $(ANDROID_NDK_HOME),$(ANDROID_NDK))
ifeq ($(NDK),)
$(error "Set ANDROID_NDK_HOME (or ANDROID_NDK) to your Android NDK directory")
endif

# Host OS triple of the NDK prebuilt tools (linux-x86_64, darwin-x86_64, ...).
HOST_PLATFORM ?= $(shell uname -s | tr '[:upper:]' '[:lower:]')-$(shell uname -m)

# Android API level to target (Android 5.0 Lollipop by default).
API ?= 21

# CPU-specific variables. Supported ABIs:
#   armeabi-v7a  -> armv7a-linux-androideabi  / arm-linux-androideabi
#   arm64-v8a    -> aarch64-linux-android     / aarch64-linux-android
#   x86          -> i686-linux-android        / i686-linux-android
#   x86_64       -> x86_64-linux-android      / x86_64-linux-android
ifeq ($(ABI),armeabi-v7a)
  HOST   := armv7a-linux-androideabi
  TARGET := arm-linux-androideabi
else ifeq ($(ABI),arm64-v8a)
  HOST   := aarch64-linux-android
  TARGET := aarch64-linux-android
else ifeq ($(ABI),x86)
  HOST   := i686-linux-android
  TARGET := i686-linux-android
else ifeq ($(ABI),x86_64)
  HOST   := x86_64-linux-android
  TARGET := x86_64-linux-android
else
$(error "Unsupported ABI '$(ABI)'. Use one of: armeabi-v7a, arm64-v8a, x86, x86_64")
endif

PREFIX := $(HOST)$(API)
TOOLCHAIN := $(NDK)/toolchains/llvm/prebuilt/$(HOST_PLATFORM)

BUILD_PREFIX := ${PWD}/build-$(ABI)
INCDIR       := $(BUILD_PREFIX)/include
LIBDIR       := $(BUILD_PREFIX)/lib
PKG_CONFIG_LIBDIR := $(BUILD_PREFIX)/lib/pkgconfig
NPROC        := $(shell nproc)

# Make the NDK clang wrappers (used by Meson for pixman and mkxp-z itself)
# available on PATH for the whole build.
export PATH := $(TOOLCHAIN)/bin:$(PATH)

# Toolchain tools
CC      := $(TOOLCHAIN)/bin/$(PREFIX)-clang
CXX     := $(TOOLCHAIN)/bin/$(PREFIX)-clang++
AS      := $(CC)
LD      := $(TOOLCHAIN)/bin/ld
AR      := $(TOOLCHAIN)/bin/llvm-ar
NM      := $(TOOLCHAIN)/bin/llvm-nm
OBJCOPY := $(TOOLCHAIN)/bin/llvm-objcopy
OBJDUMP := $(TOOLCHAIN)/bin/llvm-objdump
RANLIB  := $(TOOLCHAIN)/bin/llvm-ranlib
STRIP   := $(TOOLCHAIN)/bin/llvm-strip

# OpenSSL names its Android targets differently.
ifeq ($(ABI),armeabi-v7a)
  OPENSSL_TARGET := android-arm
else ifeq ($(ABI),arm64-v8a)
  OPENSSL_TARGET := android-arm64
else ifeq ($(ABI),x86)
  OPENSSL_TARGET := android-x86
else ifeq ($(ABI),x86_64)
  OPENSSL_TARGET := android-x86_64
endif

# Architecture flags (the NDK wrappers already set -march/-mfpu, but be explicit
# for the autotools builds that bypass the wrappers).
CROSSFLAGS :=
ifeq ($(ABI),armeabi-v7a)
  CROSSFLAGS := -march=armv7-a -mfpu=neon -mfloat-abi=softfp
else ifeq ($(ABI),arm64-v8a)
  CROSSFLAGS := -march=armv8-a
endif

# Compiler/linker flags
# -I$(INCDIR)/SDL2 is needed by packages that include <SDL.h> directly without
# using SDL2's CMake/pkg-config imported target (e.g. the sdl_ttf fork's
# Android branch, which links SDL2 by bare name and never adds its include dir).
CFLAGS  := -O2 $(CROSSFLAGS) -fPIC --sysroot=$(TOOLCHAIN)/sysroot -I$(TOOLCHAIN)/sysroot/usr/include -I$(INCDIR) -I$(INCDIR)/SDL2
LDFLAGS := -L$(LIBDIR) -lm -lz

# Meson cross file for the current ABI (used by pixman, which ships Meson).
TOP_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
MESON_CROSS := $(TOP_DIR)/meson-$(ABI).txt

# CMake arguments (using the NDK's bundled CMake toolchain)
# The NDK toolchain restricts find_* to CMAKE_FIND_ROOT_PATH (its sysroot).
# Adding our dependency prefix to CMAKE_FIND_ROOT_PATH makes cross-compiled
# libraries (Ogg, Vorbis, SDL2, ...) discoverable; the NDK appends its own
# sysroot to the list, and ONLY-mode search then covers both without ever
# leaking host paths.
CMAKE_ARGS := \
	-DCMAKE_TOOLCHAIN_FILE="$(NDK)/build/cmake/android.toolchain.cmake" \
	-DCMAKE_SYSTEM_NAME=Android \
	-DCMAKE_SYSTEM_VERSION=$(API) \
	-DANDROID_PLATFORM=$(API) \
	-DANDROID_ABI=$(ABI) \
	-DCMAKE_ANDROID_ARCH_ABI=$(ABI) \
	-DCMAKE_ANDROID_STL_TYPE=c++_shared \
	-DCMAKE_INSTALL_PREFIX="$(BUILD_PREFIX)" \
	-DCMAKE_FIND_ROOT_PATH="$(BUILD_PREFIX)" \
	-DCMAKE_PREFIX_PATH="$(BUILD_PREFIX)" \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_C_FLAGS="$(CFLAGS)" \
	-DCMAKE_SHARED_LINKER_FLAGS="$(LDFLAGS)" \
	-DCMAKE_EXE_LINKER_FLAGS="$(LDFLAGS)" \
	-DCMAKE_MODULE_LINKER_FLAGS="$(LDFLAGS)" \
	-DCMAKE_POLICY_VERSION_MINIMUM=3.10 \
	-G "Unix Makefiles"

# Autoconf environment variables
CONFIGURE_ENV := \
	CC="$(CC)" CXX="$(CXX)" AS="$(AS)" LD="$(LD)" AR="$(AR)" NM="$(NM)" \
	RANLIB="$(RANLIB)" STRIP="$(STRIP)" OBJCOPY="$(OBJCOPY)" OBJDUMP="$(OBJDUMP)" \
	CFLAGS="$(CFLAGS)" LDFLAGS="$(LDFLAGS)" \
	PKG_CONFIG_LIBDIR="$(PKG_CONFIG_LIBDIR)"

CONFIGURE_ARGS := --host=$(HOST) --prefix="$(BUILD_PREFIX)"

# Only Android 8.0+ (API 26) provides pwd.h/langinfo.h functions such as
# getpwent()/nl_langinfo(). Ruby's configure probes for them, so tell it up
# front that they don't exist on older API levels.
ifeq ($(shell test $(API) -lt 26; echo $$?),0)
	CONFIGURE_ARGS += ac_cv_header_pwd_h=no ac_cv_header_langinfo_h=no
endif

# The host Ruby that Ruby's build runs. Name it explicitly: otherwise configure
# looks for `ruby` on PATH, which may find another ABI's cross-compiled one in
# build-<abi>/bin (see build.sh).
BASERUBY := $(or $(BASERUBY),$(shell command -v ruby))

# Ruby configure arguments
RUBY_CONFIGURE_ARGS := \
	--with-baseruby=$(BASERUBY) \
	--enable-shared \
	--disable-install-doc \
	--disable-rubygems \
	--with-static-linked-ext \
	--with-out-ext=readline,dbm,gdbm,win32,win32ole,fiddle \
	--without-gmp

CONFIGURE := $(CONFIGURE_ENV) ./configure $(CONFIGURE_ARGS)
CMAKE     := $(CONFIGURE_ENV) cmake .. $(CMAKE_ARGS)

# Several of these autotools packages (libtheora in particular) ship a
# config.sub/config.guess that predates both aarch64 and Android, which makes
# `./configure --host=aarch64-linux-android` fail with "Invalid configuration".
# Refresh them from the host automake before running configure.
REFRESH_CONFIG = \
	for d in /usr/share/automake-* /usr/local/share/automake-*; do \
		if test -f "$$d/config.sub"; then \
			cp -f "$$d/config.sub" config.sub; \
			cp -f "$$d/config.guess" config.guess; \
			break; \
		fi; \
	done

.PHONY: all default init_dirs
default: all

# ---------------------------------------------------------------------------
# libogg (autotools, shared)
# ---------------------------------------------------------------------------
$(LIBDIR)/libogg.so: libogg/configure
	cd libogg && $(REFRESH_CONFIG) && ($(MAKE) distclean 2>/dev/null || true) && \
	$(CONFIGURE) --enable-shared --disable-static && $(MAKE) -j$(NPROC) && $(MAKE) install

libogg/configure: libogg/autogen.sh
	cd libogg && ./autogen.sh

# ---------------------------------------------------------------------------
# libvorbis (CMake, shared)
# ---------------------------------------------------------------------------
$(LIBDIR)/libvorbis.so: libvorbis/CMakeLists.txt $(LIBDIR)/libogg.so
	cd libvorbis && rm -rf cmakebuild && mkdir -p cmakebuild && cd cmakebuild && \
	$(CMAKE) -DBUILD_SHARED_LIBS=on && $(MAKE) -j$(NPROC) && $(MAKE) install

# ---------------------------------------------------------------------------
# libtheora (autotools, shared)
# ---------------------------------------------------------------------------
$(LIBDIR)/libtheora.so: libtheora/configure $(LIBDIR)/libogg.so
	cd libtheora && $(REFRESH_CONFIG) && ($(MAKE) distclean 2>/dev/null || true) && \
	$(CONFIGURE) --with-ogg=$(BUILD_PREFIX) --enable-shared --disable-static --disable-examples && \
	$(MAKE) -j$(NPROC) && $(MAKE) install

libtheora/configure: libtheora/autogen.sh
	cd libtheora && ./autogen.sh

# ---------------------------------------------------------------------------
# libpng (autotools, shared)
# ---------------------------------------------------------------------------
$(LIBDIR)/libpng.so: libpng/configure
	cd libpng && $(REFRESH_CONFIG) && ($(MAKE) distclean 2>/dev/null || true) && \
	$(CONFIGURE) --enable-shared --disable-static && $(MAKE) -j$(NPROC) && $(MAKE) install

# ---------------------------------------------------------------------------
# pixman (Meson; pixman's autotools does not cross-compile cleanly to Android)
# ---------------------------------------------------------------------------
$(LIBDIR)/libpixman-1.so:
	cd pixman && rm -rf _build && meson setup _build --cross-file "$(MESON_CROSS)" \
		--prefix "$(BUILD_PREFIX)" --default-library shared \
		-Darm-simd=disabled -Dneon=disabled -Da64-neon=disabled
	cd pixman && meson compile -C _build && meson install -C _build

# ---------------------------------------------------------------------------
# PhysicsFS (CMake, shared)
# ---------------------------------------------------------------------------
$(LIBDIR)/libphysfs.so: physfs/CMakeLists.txt
	cd physfs && rm -rf cmakebuild && mkdir -p cmakebuild && cd cmakebuild && \
	$(CMAKE) -DPHYSFS_BUILD_STATIC=false -DPHYSFS_BUILD_SHARED=true && \
	$(MAKE) -j$(NPROC) && $(MAKE) install

# ---------------------------------------------------------------------------
# FreeType (autotools, shared)
# ---------------------------------------------------------------------------
# autogen.sh checks out FreeType's `subprojects/dlg` submodule, copies the dlg
# sources into the tree, and generates builds/unix/configure (the real autotools
# script that the committed top-level `configure` wrapper delegates to). Use
# builds/unix/configure as the "bootstrapped" marker -- the top-level
# `configure` is a committed file and can't serve as one.
$(LIBDIR)/libfreetype.so: freetype/builds/unix/configure
	cd freetype && $(REFRESH_CONFIG) && ($(MAKE) distclean 2>/dev/null || true) && \
	$(CONFIGURE) --enable-shared --disable-static && $(MAKE) -j$(NPROC) && $(MAKE) install

freetype/builds/unix/configure: freetype/autogen.sh
	cd freetype && ./autogen.sh

# ---------------------------------------------------------------------------
# SDL2 (CMake, shared)
# ---------------------------------------------------------------------------
# SDL 2.28.1 (the mkxp-z fork's base) uses ALooper_pollAll, which newer NDKs
# mark as obsoleted (a hard compile error). Replace it with ALooper_pollOnce,
# matching SDL's own fix from 2.30.12. Do this right before compiling so it
# also repairs a tree that was already configured.
$(LIBDIR)/libSDL2.so: SDL2/CMakeLists.txt
	cd SDL2 && sed -i 's/ALooper_pollAll/ALooper_pollOnce/' src/sensor/android/SDL_androidsensor.c && \
	rm -rf cmakebuild && mkdir -p cmakebuild && cd cmakebuild && \
	$(CMAKE) -DBUILD_SHARED_LIBS=on -DSDL_TEST=off && $(MAKE) -j$(NPROC) && $(MAKE) install

# ---------------------------------------------------------------------------
# SDL2_image (CMake, shared)
# ---------------------------------------------------------------------------
$(LIBDIR)/libSDL2_image.so: SDL2_image/CMakeLists.txt $(LIBDIR)/libSDL2.so
	cd SDL2_image && rm -rf cmakebuild && mkdir -p cmakebuild && cd cmakebuild && \
	$(CMAKE) -DBUILD_SHARED_LIBS=on -DSDL2IMAGE_VENDORED=on -DSDL2IMAGE_JXL=off -DSDL2IMAGE_SAMPLES=off && \
	$(MAKE) -j$(NPROC) && $(MAKE) install

# ---------------------------------------------------------------------------
# SDL2_ttf (CMake, shared)
# ---------------------------------------------------------------------------
$(LIBDIR)/libSDL2_ttf.so: SDL2_ttf/CMakeLists.txt $(LIBDIR)/libSDL2.so $(LIBDIR)/libfreetype.so
	cd SDL2_ttf && rm -rf cmakebuild && mkdir -p cmakebuild && cd cmakebuild && \
	$(CMAKE) -DBUILD_SHARED_LIBS=on -DSDL2TTF_VENDORED=off -DSDL2TTF_SAMPLES=off && \
	$(MAKE) -j$(NPROC) && $(MAKE) install

# ---------------------------------------------------------------------------
# SDL2_sound (CMake, shared)
# ---------------------------------------------------------------------------
$(LIBDIR)/libSDL2_sound.so: SDL2_sound/CMakeLists.txt $(LIBDIR)/libSDL2.so $(LIBDIR)/libogg.so $(LIBDIR)/libvorbis.so
	cd SDL2_sound && rm -rf cmakebuild && mkdir -p cmakebuild && cd cmakebuild && \
	$(CMAKE) -DSDLSOUND_BUILD_SHARED=true -DSDLSOUND_BUILD_TEST=false && \
	$(MAKE) -j$(NPROC) && $(MAKE) install

# ---------------------------------------------------------------------------
# uchardet (CMake, shared)
# ---------------------------------------------------------------------------
$(LIBDIR)/libuchardet.so: uchardet/CMakeLists.txt
	cd uchardet && rm -rf cmakebuild && mkdir -p cmakebuild && cd cmakebuild && \
	$(CMAKE) -DBUILD_SHARED_LIBS=on && $(MAKE) -j$(NPROC) && $(MAKE) install

# ---------------------------------------------------------------------------
# libiconv (autotools, shared)
# ---------------------------------------------------------------------------
$(LIBDIR)/libiconv.so: libiconv/configure
	cd libiconv && $(REFRESH_CONFIG) && ($(MAKE) distclean 2>/dev/null || true) && \
	$(CONFIGURE) --enable-shared --disable-static && $(MAKE) -j$(NPROC) && $(MAKE) install

# ---------------------------------------------------------------------------
# OpenAL Soft (CMake, shared)
# ---------------------------------------------------------------------------
$(LIBDIR)/libopenal.so: openal/CMakeLists.txt
	cd openal && rm -rf cmakebuild && mkdir -p cmakebuild && cd cmakebuild && \
	$(CMAKE) -DLIBTYPE=SHARED \
		-DALSOFT_REQUIRE_OPENSL=ON -DALSOFT_EXAMPLES=OFF -DALSOFT_UTILS=OFF && \
	$(MAKE) -j$(NPROC) && $(MAKE) install

# ---------------------------------------------------------------------------
# OpenSSL (shared)
# ---------------------------------------------------------------------------
# Like the other dependencies, configure OpenSSL from a clean tree for every
# ABI: the source tree is shared, and a tree configured for another ABI would
# build and install that ABI instead.
# OpenSSL finds the NDK through ANDROID_NDK_ROOT before ANDROID_NDK_HOME, and
# fails if that isn't the NDK whose clang is on PATH: always point it at $(NDK).
$(LIBDIR)/libssl.so: openssl/Configure
	cd openssl && ($(MAKE) distclean 2>/dev/null || true) && \
	ANDROID_NDK_ROOT="$(NDK)" CFLAGS="-Wno-macro-redefined" ./Configure $(OPENSSL_TARGET) \
		shared -D__ANDROID_API__=$(API) \
		--prefix="$(BUILD_PREFIX)" --openssldir="$(BUILD_PREFIX)" && \
	$(MAKE) -j$(NPROC) && $(MAKE) install_sw

# ---------------------------------------------------------------------------
# Ruby (autotools, shared)
# ---------------------------------------------------------------------------
# Ruby's build artifacts live in a shared source tree and get contaminated
# across ABIs / prior host builds, so always distclean before reconfiguring.
$(LIBDIR)/libruby.so.3.1: ruby/configure $(LIBDIR)/libssl.so
	cd ruby && ($(MAKE) distclean 2>/dev/null || true) && \
	DLDFLAGS="-Wl,-soname,libruby.so" $(CONFIGURE) $(RUBY_CONFIGURE_ARGS) && \
	$(MAKE) -j$(NPROC) && $(MAKE) install
	# We build libruby with "-Wl,-soname,libruby.so" so that both
	# System.loadLibrary("ruby") and libmkxp-z.so's DT_NEEDED agree on a single
	# "libruby.so" file. That flag would otherwise leak into ruby-3.1.pc's
	# "Libs:" line and corrupt libmkxp-z.so's own soname, so clear it here.
	sed -i 's/^DLDFLAGS=.*/DLDFLAGS=/' $(PKG_CONFIG_LIBDIR)/ruby-3.1.pc

ruby/configure: ruby/configure.ac
	cd ruby && autoreconf -i

# ---------------------------------------------------------------------------
# Convenience targets
# ---------------------------------------------------------------------------
init_dirs:
	@mkdir -p $(LIBDIR) $(INCDIR)

# Android's NDK provides zlib but no zlib.pc. libpng's pkg-config metadata
# declares a dependency on zlib, so generate a minimal zlib.pc describing the
# NDK's libz (which the compiler already locates via --sysroot).
$(PKG_CONFIG_LIBDIR)/zlib.pc:
	@mkdir -p $(PKG_CONFIG_LIBDIR)
	@printf 'Name: zlib\nDescription: zlib compression library\nVersion: 1.2.13\nLibs: -lz\nCflags:\n' > $@

deps-core: $(LIBDIR)/libtheora.so $(LIBDIR)/libvorbis.so $(LIBDIR)/libpng.so \
	$(LIBDIR)/libpixman-1.so $(LIBDIR)/libphysfs.so $(LIBDIR)/libfreetype.so \
	$(LIBDIR)/libSDL2.so $(LIBDIR)/libSDL2_image.so $(LIBDIR)/libSDL2_ttf.so \
	$(LIBDIR)/libSDL2_sound.so $(LIBDIR)/libuchardet.so $(LIBDIR)/libiconv.so \
	$(LIBDIR)/libopenal.so $(LIBDIR)/libssl.so

all: deps-core $(LIBDIR)/libruby.so.3.1 $(PKG_CONFIG_LIBDIR)/zlib.pc
