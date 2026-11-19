# Building and running Pokessentials

Pokessentials runs Pokémon Essentials v21.1 scripts straight from `src/`, at a
**256×192** resolution with half-size graphics, on desktop and Android. This
guide covers everything from installing the Essentials assets to packaging
the game.

- [Quick start](#quick-start)
- [Requirements](#requirements)
- [How the build works](#how-the-build-works)
- [Make targets](#make-targets)
- [game.sh](#gamesh)
- [Asset tools](#asset-tools)
- [Graphics pipeline](#graphics-pipeline)
- [Resolution, scaling and fonts](#resolution-scaling-and-fonts)
- [Android](#android)
- [Converting scripts and plugins](#converting-scripts-and-plugins)
- [Troubleshooting](#troubleshooting)

## Quick start

```bash
tools/scripts/install_assets.sh
```

```bash
make mkxp
```

```bash
./game.sh
```

1. `install_assets.sh` copies the graphics, audio, PBS files and map data of the
   Essentials release in `lib/pokemon-essentials` into `src/assets/`.
2. `make mkxp` builds the mkxp-z engine into `build/engine/`. You can skip this
   if you already have mkxp-z (see [game.sh](#gamesh)).
3. `./game.sh` builds `build/` and starts the game in debug mode. The first
   launch compiles the PBS files.

## Requirements

**Building the game folder**

- GNU make, bash
- Python 3 with [Pillow](https://pypi.org/project/Pillow/) (`python3 -m pip install Pillow`)
- Ruby (any 3.x) for `tools/scripts/halve_data.rb`
- `unzip` (only to install assets from a `.zip`) and `zip` (only for `make android`)
- `xvfb-run` (only for `make compile` on a machine without a display)

**Building mkxp-z for Linux (`make mkxp`)**

gcc/g++, cmake, meson, ninja, pkg-config, git, autoconf, automake, libtool,
bison, nasm and the X11/OpenGL/audio development headers. On Debian/Ubuntu:

```bash
sudo apt install build-essential cmake meson ninja-build pkg-config git autoconf automake libtool bison nasm libgl-dev libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxi-dev libxinerama-dev libxss-dev libasound2-dev libpulse-dev libpixman-1-dev libuchardet-dev libdbus-1-dev zlib1g-dev libbz2-dev libffi-dev libyaml-dev
```

**Android (`make apk`)**: Android NDK r25+ (`ANDROID_NDK_HOME`), the Android
SDK (`ANDROID_HOME`), JDK 11+, plus the meson/cmake/autotools tools above.
See `lib/mkxp-z/android/README.md`.

## How the build works

`make` turns `src/` into a self-contained game folder, `build/`:

| Source | Build output | What happens |
| --- | --- | --- |
| `src/data/` | `build/Scripts/` | copied |
| `src/loader.rb` | `build/loader.rb` | copied; mkxp-z runs it (`customScript`) |
| `src/mkxp.json`, `src/Game.ini` | `build/` | copied |
| `src/assets/graphics/` | `build/Graphics/` | **halved** (see [Graphics pipeline](#graphics-pipeline)) |
| `src/assets/audio/` | `build/Audio/` | copied |
| `src/assets/fonts/` | `build/Fonts/` | copied |
| `src/assets/pbs/` | `build/PBS/` | copied (newer files in `build/` are kept) |
| `src/assets/data/` | `build/Data/` | pixel values **halved** (`halve_data.rb`) |
| `src/assets/plugins/` | `build/Plugins/` | copied |

Every step is incremental, so a rebuild only touches what changed.

### The script loader

mkxp-z normally reads `Data/Scripts.rxdata`. Instead, `mkxp.json` points its
`customScript` option at `loader.rb`, which:

- loads every `.rb` file in `Scripts/` (or in `$POKESSENTIALS_SCRIPTS`). In
  each folder, files are loaded before subfolders, and both are sorted by
  name, so the `001_`, `002_`… prefixes decide the order. This is the same
  order as Essentials' own `Scripts.rxdata`.
- runs each file at top level with its real path, so error messages and
  backtraces name the actual file.
- fills `$RGSS_SCRIPTS`, which Essentials uses for translations and error
  messages.
- restarts the scripts when F12 (reset) is pressed.

To add a script, drop a file with the right number prefix into `src/data/`.

### Editing PBS files with the debug editors

The in-game debug editors write to `build/PBS/`. `make` never overwrites a
file there that is newer than its source. Run `make pull-pbs` to copy your
edits back into `src/assets/pbs/` before committing.

## Make targets

| Target | Description |
| --- | --- |
| `make` / `make build` | Build `build/` |
| `make run` / `make debug` | Build and play in debug mode |
| `make release` | Build and play without debug mode |
| `make live` | Play using the scripts in `src/data/` directly, with no copy |
| `make compile` | Compile PBS into `build/Data/*.dat` headlessly, then exit |
| `make mkxp` | Build mkxp-z (Linux) into `build/engine/` |
| `make desktop` | Package `build/`, the engine and `play.sh` into `dist/pokessentials-linux.tar.gz` |
| `make android` | Package `build/` as `dist/pokessentials-android.zip` (+ `.obb`) |
| `make apk` | Build the mkxp-z Android app into `dist/` |
| `make install-assets` / `make uninstall-assets` | See [Asset tools](#asset-tools) |
| `make pull-pbs` | Copy PBS files changed by the debug editors back to `src/assets/pbs/` |
| `make clean-data` | Remove compiled data (`build/Data/*.dat`) |
| `make clean` | Remove `build/`, keeping the built engine |
| `make distclean` | Remove `build/` and `dist/` |
| `make help` | List the targets |

## game.sh

```bash
./game.sh [--release] [--no-build] [--live] [--compile] [-- engine arguments]
```

| Option | Description |
| --- | --- |
| *(none)* | Build, then run in debug mode (compile prompt, debug menu) |
| `--release` | Run without debug mode |
| `--no-build` | Skip `make build` |
| `--live` | Load scripts from `src/data/` instead of `build/Scripts/`, so script edits need no rebuild |
| `--compile` | Compile PBS data and exit (headless via `xvfb-run` if there is no display) |

The engine is the first one found of:

1. `$MKXPZ`, for example `MKXPZ=~/mkxp-z/mkxp-z ./game.sh`
2. `build/engine/mkxp-z` (from `make mkxp`)
3. `mkxp-z` on your `PATH`

mkxp-z on Linux uses the `SRCDIR` environment variable as its game folder,
which `game.sh` sets to `build/`.

## Asset tools

All scripts are in `tools/scripts/`.

| Script | What it does |
| --- | --- |
| `extract_assets.sh [SRC]` | Finds an Essentials release in a folder (default `lib/pokemon-essentials`), or unpacks a `.zip` of one into `build/.essentials`. |
| `install_assets.sh [--force] [SRC]` | Copies `Graphics/` → `src/assets/graphics/`, `Audio/` → `src/assets/audio/`, `soundfont.sf2` → `src/assets/audio/`, `PBS/*.txt` → `src/assets/pbs/`, and `Data/*.rxdata` (except scripts) → `src/assets/data/`. |
| `uninstall_assets.sh [--force]` | Removes exactly the files `install_assets.sh` installed. |
| `clean_data.sh [--all]` | Removes compiled data and staging (`--all`: the whole `build/`). |
| `resize_graphics.py` | The graphics halver used by `make`. |
| `halve_data.rb` | The map/animation data converter used by `make`. |
| `halve_script_coords.rb` | Converts Essentials-style scripts to 256×192 (see [below](#converting-scripts-and-plugins)). |
| `sync_dir.py` | Incremental folder copy used by `make`. |
| `build_engine.sh`, `build_apk.sh`, `play.sh` | Engine/APK builds and the packaged-build launcher. |

How installed files are tracked:

- Every installed file is recorded with its checksum in
  `src/assets/.installed_manifest`.
- Running `install_assets.sh` again updates installed files, but skips any file
  you changed or added yourself. `--force` overwrites them anyway.
- `uninstall_assets.sh` keeps files you changed, unless you pass `--force`.

Installed files are added to `.git/info/exclude`, so the thousands of Essentials
files are never committed by accident. Your own files in `src/assets/` are
tracked as usual. To commit an Essentials file you edited, use `git add -f`.

## Graphics pipeline

Source graphics in `src/assets/graphics/` stay at Essentials' original 2× size.
`make` halves them into `build/Graphics/` with
`tools/scripts/resize_graphics.py`:

- **Nearest-neighbour only.** Every game pixel stays one uniform size (no
  "mixels") and no new colours are invented.
- **Clean-2× check.** Most Essentials art is a 2× upscale of 1× art, so halving
  it loses nothing. Art that isn't is still halved, but listed in
  `build/resize_report.txt`. For Essentials 21.1 that's 152 files: mostly
  battle animation sheets, all tilesets, transitions and fogs. Redraw them at
  1× in `src/assets/graphics/` to replace the lossy versions.
- **96×96 battle sprites.** Every battle sprite frame comes out exactly 96×96:
  - Pokémon front/back sprites (all forms, shiny or not)
  - egg battler sprites and the hatching sheet
  - trainer front sprites and back-sprite sheets (5 frames → 480×96)

  Frames smaller than 96×96 after halving (Essentials' 160×160 sprites become
  80×80) are padded with transparency at the bottom centre. That matches how
  battlers are anchored (`ox = width / 2`, `oy = height`), so they stand in
  the same place. A sprite that can't fit in 96×96 without losing opaque
  pixels stops the build with an error.
- Files that aren't PNGs are copied unchanged. Outputs whose source was
  deleted are removed.

`halve_data.rb` does the same for pixel values stored in game data:

- Show/Move Picture commands in maps, common events and troops
- RMXP animation cells (`Animations.rxdata`)
- Essentials battle animations (`PkmnAnimations.rxdata`)

Tile-based values are left alone. Pokémon sprite metrics in PBS are already in
1× pixels and are used as-is.

## Resolution, scaling and fonts

- `Settings::SCREEN_WIDTH`/`SCREEN_HEIGHT` are 256×192 and tiles are 16×16, so
  the same 16×12 tiles fit on screen as in stock Essentials. All hard-coded
  coordinates in `src/data/` were halved to match.
- **Window scaling is always a whole number.** `src/mkxp.json` turns on
  mkxp-z's integer scaling with nearest-neighbour filtering and no "last mile"
  stretch. However the player resizes the window, the picture is shown at the
  largest whole multiple that fits (1×, 2×, 3×…), with black borders filling
  the rest.
- The window starts at 3× (768×576), from `Settings::SCREEN_SCALE` and
  `defScreenW`/`defScreenH`.
- The Options screen offers 1×, 2×, 3×, 4× and Fullscreen.
- **Fonts.** The Power fonts are pixel fonts. mkxp-z treats the font size as
  the character cell height, like Windows does, so the sizes that draw crisp
  1× pixels are 16 (Power Green / Narrow) and 13 (Power Green Small). They are
  set in `MessageConfig`. `fontHeightReporting: 1` in `mkxp.json` stops the
  bottom row of the glyphs from being cut off.

## Android

The Android app is the mkxp-z wrapper in `lib/mkxp-z/android`. It loads a game
folder (any folder with a `Game.ini`) from a `.zip`/`.obb` archive. `build/`
works unchanged on Android:

- relative paths
- case-insensitive asset lookup (`pathCache`)
- a loader that only uses core Ruby and Zlib

Android can't compile PBS files at runtime, so packaging compiles them first.

```bash
make android
```

This runs `make compile` (headless) and writes `dist/pokessentials-android.zip`
and `dist/main.1.com.mkxpz.obb`. Then either:

- install the app and load the zip from its slide-out menu, or
- copy the `.obb` to `Android/obb/com.mkxpz/` on the device.

Change the package name with `make android ANDROID_PACKAGE=…`.

To build the app itself:

```bash
ANDROID_NDK_HOME=/path/to/ndk ANDROID_HOME=/path/to/sdk make apk
```

Set `ABIS=arm64-v8a` to build a single ABI.

How the game behaves on Android:

- `pbIsAndroid?` returns true.
- The game always runs fullscreen with integer scaling and borders.
- The Options screen hides the screen-size setting.

## Converting scripts and plugins

`tools/scripts/halve_script_coords.rb` (Ruby 3.3+, uses Prism) halves the
hard-coded pixel values in Essentials-style scripts:

- arguments of `Viewport.new`, `Rect.new`, `blt`, `draw_text`, `fill_rect`,
  window constructors, PictureEx moves and similar calls
- `x`/`y`/`width`/`height` assignments
- text and image position arrays
- constants and variables with coordinate-like names

Use it on plugins written for stock Essentials:

```bash
ruby tools/scripts/halve_script_coords.rb --odd src/assets/plugins/MyPlugin
```

**Review the diff afterwards.** The tool only knows patterns. It can't tell a
pixel value from a count or an index that happens to sit in the same place.
`--odd` lists odd values that couldn't be halved exactly, and `--dry-run`
shows what would change without writing anything.

## Troubleshooting

- **"no mkxp-z engine found"**: run `make mkxp`, set `MKXPZ`, or put `mkxp-z`
  on your `PATH`.
- **`make mkxp` fails to download a dependency**: `lib/mkxp-z/linux/Makefile`
  downloads its dependencies from GitHub, gitlab.freedesktop.org and
  ftp.gnu.org. If some of these are unreachable, install the matching system
  `-dev` packages (pixman, uchardet, dbus, iconv come with most distros), build
  the remaining targets with `make -C lib/mkxp-z/linux <target>`, and run
  `SKIP_DEPS=1 make mkxp`.
- **No sound / "Could not detect an available audio device"**: on machines
  without audio, set `ALSOFT_DRIVERS=null` (done automatically for
  `--compile`).
- **Blurry or clipped text**: keep the font sizes in `MessageConfig` at 16/13/16
  and `"fontHeightReporting": 1`. Other sizes are not pixel-aligned.
- **A graphic looks rough**: check `build/resize_report.txt`. It's probably art
  that wasn't a clean 2× upscale. Draw a 1× version in `src/assets/graphics/`.
- **Script calls in events use 512×384 coordinates**: `halve_data.rb` can't
  convert Ruby code inside event script commands. Halve those numbers by hand.
