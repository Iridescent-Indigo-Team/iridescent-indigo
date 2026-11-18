# Android support

This directory turns mkxp-z into a build target for Android and wraps it in a
native Android application.

The native side reuses the repository's existing Meson build: `meson setup
--cross-file android/meson-<abi>.txt` produces `libmkxp-z.so`, which the Java
wrapper (`app/`) loads through SDL2's `SDLActivity` bootstrap. This keeps
Android a first-class target of the *same* source tree rather than a
separate, pinned copy.

```
android/
├── app/                    # Gradle application (the "wrapper")
│   ├── build.gradle
│   └── src/main/
│       ├── AndroidManifest.xml
│       ├── java/com/mkxpz/          # MainActivity + on-screen gamepad + launcher menu
│       ├── java/org/libsdl/app/     # SDL2 Java bootstrap
│       └── res/                     # layouts, drawables, strings
├── deps/                   # dependency download + cross-compile (Makefile)
├── meson-*.txt             # Meson cross files for each ABI
├── build.sh                # one-shot native build orchestration
└── README.md
```

## Requirements

- Android NDK (r25+ recommended). Set `ANDROID_NDK_HOME`.
- Meson (>= 0.56) and Ninja.
- CMake, autoconf/automake/libtool, pkg-config (used to build the dependencies).
- JDK 11+ and Android SDK (for Gradle / the APK).

## Building

### 1. Build the native library (all ABIs)

```sh
cd android
ANDROID_NDK_HOME=/path/to/ndk ./build.sh
```

`build.sh` downloads the dependency sources into `android/deps/`, cross-compiles
them into `android/deps/build-<abi>/`, runs the Meson cross-build for each ABI,
and stages `libmkxp-z.so` together with its runtime libraries into
`app/src/main/jniLibs/<abi>/`.

To build a single ABI (faster for testing):

```sh
cd android
ABIS=arm64-v8a ANDROID_NDK_HOME=/path/to/ndk ./build.sh
```

### 2. Build the APK

```sh
cd android
./gradlew assembleDebug        # or assembleRelease
```

`app/build.gradle` runs `build.sh` automatically as part of `preBuild`, so
`./gradlew assembleDebug` alone is enough for a full build.

### 3. Install and run

1. Install the APK on your device.
2. Get a game onto the device by launching the app and using the **slide-out
   menu** (swipe right from the left screen edge, or tap the grab handle) to
   pick a `.zip`/`.obb` game archive. It is extracted into the app's own
   external files directory (`/storage/emulated/0/Android/data/com.mkxpz/files/mkxp-z`),
   which needs no storage permissions and is removed on uninstall.
3. Launch the app. No storage permissions are required.

When no game is found, mkxp-z keeps the native engine paused and shows the
slide-out menu so you can load a game. The chosen game folder is remembered
across launches (via `SharedPreferences`); loading a *different* archive while
a game is running restarts the process, since the Ruby VM cannot be
re-initialized in place.

## How the native build works (without Gradle)

`build.sh` is a thin wrapper around two steps you can also run by hand:

```sh
cd android/deps
./get_deps.sh
make ABI=arm64-v8a              # cross-compile SDL2, Ruby, OpenAL, ...

cd ..
source deps/vars.sh             # sets PKG_CONFIG_LIBDIR/CFLAGS/LDFLAGS/PATH
ABI=arm64-v8a
meson setup build-arm64-v8a --cross-file meson-arm64-v8a.txt
meson compile -C build-arm64-v8a
```

The cross files (`meson-*.txt`) expect the NDK clang wrappers (for example
`aarch64-linux-android21-clang`) to be on `PATH`; `deps/vars.sh` adds them.

## Notes and caveats

- **Graphics** use the GLES2 backend (`-DGLES2_HEADER`); this is forced for
  Android in `meson.build`.
- **MIDI**: FluidSynth is not part of the Android dependency set, so MIDI
  playback falls back to OpenAL's system soundfont (set `midiSoundFont` in
  `mkxp.json`). Set `-Dshared_fluid=false` is the default for Android.
- **Ruby stdlib**: the dependency build links Ruby's native extensions
  statically (`--with-static-linked-ext`), so `require 'zlib'` and friends work
  without bundling `.so` extensions. Pure-Ruby stdlib files are *not* bundled;
  games that need them should ship them in the game folder and add the folder
  to `rubyLoadpath` in `mkxp.json`.
- **Storage**: game files live in the app's own external files directory and
  save data in the app's private data directory, so no storage permissions are
  required. Shared external storage is not used.
- **Launcher icon**: a placeholder vector drawable is used (`res/drawable/
  ic_launcher.xml`). Replace it with proper raster mipmaps for a polished icon.
- The Gradle wrapper jar is not committed; run `gradle wrapper` (or open the
  project in Android Studio) once to generate `gradlew`.

## Structure of the core changes

- `src/system/system.h` / `src/system/systemImpl.cpp` — Android platform id and
  locale/user-name handling via JNI.
- `src/filesystem/filesystemImpl.{h,cpp}` — `directoryExists()` and an Android
  default game root.
- `src/main.cpp` — Android startup: game folder from the Java `GAME_PATH` field
  and landscape orientation hint.
- `src/eventthread.cpp` — FPS counter routed to the Java overlay.
- `binding/android-binding.cpp` — the `Android` Ruby module (device info,
  vibration, multi-window).
- `meson.build` / `src/meson.build` / `binding/meson.build` — Android host
  handling (shared library output, GLES2, Android-specific link flags).
