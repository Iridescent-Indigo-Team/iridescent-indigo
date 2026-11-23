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
- [Automated builds](#automated-builds)
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
   Game data (PBS) is edited as JSON in `src/pbs/`, which is already in the
   repository (see [PBS_JSON.md](PBS_JSON.md)).
2. `make mkxp` builds the mkxp-z engine into `build/engine/`. You can skip this
   if you already have mkxp-z (see [game.sh](#gamesh)).
3. `./game.sh` builds `build/` and starts the game in debug mode. The first
   launch compiles the PBS files.

## Requirements

Git LFS is not needed: all assets come with a normal `git clone`.

**Building the game folder**

- GNU make, bash
- Python 3 with [Pillow](https://pypi.org/project/Pillow/) (`python3 -m pip install Pillow`)
- Ruby (any 3.x) for `tools/scripts/halve_data.rb`
- `unzip` (only to install assets from a `.zip`) and `zip` (only for `make android`)
- `xvfb-run` (only for `make compile` on a machine without a display)
- [Tiled](https://www.mapeditor.org) 1.10+ to edit maps (see [TILED.md](TILED.md))

**Building mkxp-z for Linux (`make mkxp`)**

gcc/g++, cmake, meson, ninja, pkg-config, git, autoconf, automake, libtool,
bison, nasm, xxd, **Ruby** (an installed Ruby is needed to build mkxp-z's own Ruby
3.1 from source) and the X11/OpenGL/audio development headers. On
Debian/Ubuntu:

```bash
sudo apt install ruby build-essential cmake meson ninja-build pkg-config git autoconf automake libtool bison nasm xxd libgl-dev libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxi-dev libxinerama-dev libxss-dev libasound2-dev libpulse-dev libpixman-1-dev libuchardet-dev libdbus-1-dev zlib1g-dev libbz2-dev libffi-dev libyaml-dev
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
| `src/pbs/` (JSON) | `build/PBS/` | validated and exported as PBS files (see [PBS_JSON.md](PBS_JSON.md)); until `src/pbs/` exists, `src/assets/pbs/` is copied instead |
| `src/tiled/` (Tiled maps) | `build/Data/Map*.rxdata`, `MapInfos`, `Tilesets`, `CommonEvents`, `System`, `atmospheres.dat`; the map datasets of `build/PBS/` | compiled once `src/tiled/maps/registry.json` exists (see [TILED.md](TILED.md)) |
| `src/assets/data/` | `build/Data/` | pixel values **halved** (`halve_data.rb`); files compiled from `src/tiled` are skipped |
| `src/assets/plugins/` | `build/Plugins/` | copied |
| `src/assets/locales/` (CSV) | `build/Data/messages_<lang>_*.dat`, `build/Graphics/Locales/` | translations validated and compiled (see [LOCALIZATION.md](LOCALIZATION.md)) |

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

### Editing maps

Maps are made in Tiled: `make import-rxdata` imports RPG Maker XP's maps once,
then `./tiled.sh` opens the project. See [TILED.md](TILED.md).

### Editing PBS files with the debug editors

The in-game debug editors write to `build/PBS/`. Run `make pull-pbs` to import
their changes into the JSON in `src/pbs/` before committing. `make` never
overwrites a PBS file in `build/PBS/` that changed since it was exported; it
stops and asks you to run `make pull-pbs` first (or `make pbs FORCE=1` to
throw those changes away). See [PBS_JSON.md](PBS_JSON.md).

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
| `make import-pbs` | Import `src/assets/pbs/*.txt` into the JSON in `src/pbs/` |
| `make pbs` | Validate `src/pbs/` and export it to `build/PBS/` (`FORCE=1` overwrites debug-editor changes) |
| `make pull-pbs` | Import PBS files changed by the debug editors (`build/PBS/`) into `src/pbs/` |
| `make validate-pbs` | Check the JSON in `src/pbs/` |
| `make pbs-schema` | Dump the PBS schemas from the engine into `tools/importer/pbs/engine_schema.json` |
| `make test-pbs` | Run the PBS ⇄ JSON converter's tests |
| `make locales` | Validate the translation CSVs and compile them into `build/` (`LANGS=de,fr`, `STRICT=1`) |
| `make update-locales` | Write the current English text into every language's CSVs (keeps translations) |
| `make validate-locales` | Check the translations (`VERBOSE=1` lists every warning) |
| `make test-locales` | Run the localization tools' tests |
| `make check-format` | Check the formatting of the Ruby and JSON changed since `BASE` (default `origin/main`); see [CONTRIBUTING.md](CONTRIBUTING.md#formatting) |
| `make format` | Fix the formatting of the Ruby and JSON changed since `BASE` |
| `make clean-data` | Remove compiled data (`build/Data/*.dat`) |
| `make clean` | Remove `build/`, keeping the built engine |
| `make distclean` | Remove `build/` and `dist/` |
| `make help` | List the targets |

## game.sh

```bash
./game.sh [--release] [--no-build] [--live] [--compile] [--dump-schema FILE] [-- engine arguments]
```

| Option | Description |
| --- | --- |
| *(none)* | Build, then run in debug mode (compile prompt, debug menu) |
| `--release` | Run without debug mode |
| `--no-build` | Skip `make build` |
| `--live` | Load scripts from `src/data/` instead of `build/Scripts/`, so script edits need no rebuild |
| `--compile` | Compile PBS data and exit (headless via `xvfb-run` if there is no display) |
| `--dump-schema FILE` | Write the PBS schemas of all GameData classes to `FILE` as JSON and exit (headless like `--compile`) |

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
| `ground_battlers.py` | Recalculates the battle sprite metrics so every Pokémon stands on the ground (`make ground-battlers`, see [Battler positions](#battler-positions)). |
| `halve_data.rb` | The map/animation data converter used by `make`. |
| `halve_script_coords.rb` | Converts Essentials-style scripts to 256×192 (see [below](#converting-scripts-and-plugins)). |
| `sync_dir.py` | Incremental folder copy used by `make`. |
| `build_engine.sh`, `build_apk.sh`, `play.sh` | Engine/APK builds and the packaged-build launcher. |

How installed files are tracked:

- Every installed file is recorded with its checksum in
  `src/assets/.installed_manifest`.
- Running `install_assets.sh` again updates installed files, but skips any file
  you changed or added yourself. `--force` overwrites them anyway.
- Files it copies or updates get the current time, so the next `make` rebuilds
  them (e.g. new art committed to `lib/pokemon-essentials/Graphics`).
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
- **3× back sprites.** The Generation 9 Pack's back sprites are 288×288: 3×
  upscales of 96×96 art, drawn 1.5× larger than the front sprites. Battle
  frames of 288×288 are divided by 3 instead of 2, so they come out as clean
  96×96 sprites. They are full-body, unlike the stock back sprites (which are
  cut off at the bottom and hidden behind the message box), so their metrics
  are worked out from the sprites (see [Battler positions](#battler-positions)).
  A few stock back sprites the pack doesn't replace (`PICHU_2`, `ARCEUS_9`,
  some female and Shadow variants) are still cut off.
- Files that aren't PNGs are copied unchanged. Outputs whose source was
  deleted are removed.

`halve_data.rb` does the same for pixel values stored in game data:

- Show/Move Picture commands in maps, common events and troops
- RMXP animation cells (`Animations.rxdata`)
- Essentials battle animations (`PkmnAnimations.rxdata`)

Tile-based values are left alone. Pokémon sprite metrics in PBS are already in
1× pixels and are used as-is.

## Battler positions

A battler sprite is anchored at its bottom centre, on its side's base position
(`Battle::Scene.pbBattlerPosition`), then moved by its `BackSprite` or
`FrontSprite` metrics in `src/pbs/pokemon_metrics`. The metrics are worked out
from the sprites so every Pokémon's feet (the lowest opaque row of its 96×96
frame) stand on a ground line:

| Side | Ground line | Why |
| --- | --- | --- |
| Player (back sprites) | `PLAYER_BASE_Y + PLAYER_FEET_OFFSET` (y 140) | Above the message box (y 144), so full-body back sprites show their feet. |
| Foe (front sprites) | `FOE_BASE_Y + FOE_FEET_OFFSET` (y 92) | Where the faint animation crops the sprite. |

The offsets are constants in `Battle::Scene`
(`src/data/011_Battle/004_Scene/001_Battle_Scene.rb`).

- **Floating Pokémon** use `FrontSpriteAltitude`: the front sprite is drawn
  that much higher at runtime and its shadow stays on the base. The back
  sprite's y is raised by the same amount.
- **Cut-off back sprites** (a wide run of opaque pixels along the bottom row)
  have their cut edge on the base position instead, behind the message box.
- **x offsets and shadows** can't be worked out from the sprites and are kept.
- **Shadows.** Foe shadows are centred on the foe's base, moved by `ShadowX`.
  Player shadows are centred on the player's ground line (y 140, partly behind
  the message box), moved by the `BackSprite` x, and scaled by
  `Battle::Scene::PLAYER_SHADOW_ZOOM` (1.5×) to match the larger back sprites.

To recalculate the metrics after adding or changing sprites:

```sh
make ground-battlers                 # rewrite src/pbs/pokemon_metrics
make ground-battlers ARGS=--check    # only report; exit 1 if anything would change
make ground-battlers ARGS="--species PIKACHU,ZUBAT --verbose"
```

`tools/scripts/ground_battlers.py` reads the sprites from `src/assets/graphics`
(or `lib/pokemon-essentials/Graphics` if no art is installed) and shrinks them
exactly as the build does. It also adds metrics entries for forms that have
their own sprites but no entry yet, and lists back sprites that are still cut
off.

`--keep-hover` is a one-time migration for metrics that baked a floating
Pokémon's hover into its y value, as the Generation 9 Pack's did: a front
sprite whose metrics lift it at least `--hover-min` pixels (default 6) off the
ground gets that lift as its `FrontSpriteAltitude`. The metrics in this repo
have already been migrated, so don't use it again: a new sprite whose feet sit
higher in its frame would look like a hover. To make a Pokémon float, set its
`front_sprite_altitude` and run the tool. In the game, **Debug > PBS editors > Auto-set pokemon_metrics.txts** and the
sprite positioner's auto-position use the same rules (`pbGroundedSpriteY`).

Move animations aim at the centre of each battler's sprite frame, relative to
`FOCUSUSER_X/Y` and `FOCUSTARGET_X/Y`, so they follow the sprites wherever the
metrics put them.

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

## Automated builds

`.github/workflows/build.yml` builds the game on GitHub every Monday, so a
broken platform shows up without anyone building it by hand:

| Job | What it does | Artifact |
| --- | --- | --- |
| Linux | `make mkxp`, `install_assets.sh`, `make desktop`, `make android` | `pokessentials-linux` (the desktop package), `pokessentials-android-game` (the zip and `.obb` for the Android app) |
| Windows | builds mkxp-z with MSYS2 (`lib/mkxp-z/windows`) and packages it with the compiled game folder from the Linux job | `pokessentials-windows` |
| Android | `make apk` for every ABI (NDK r27d, JDK 17) | `pokessentials-android-apk` |

It also runs for pull requests that change the build (the workflow, the
Makefile, `game.sh`, the build scripts or `lib/mkxp-z`), and can be started by
hand from the repository's **Actions** tab (**Build** > **Run workflow**).
Artifacts are kept for 14 days.

`.github/workflows/format.yml` checks the formatting of every push and pull
request (see [CONTRIBUTING.md](CONTRIBUTING.md#formatting)).

## Troubleshooting

- **"no mkxp-z engine found"**: run `make mkxp`, set `MKXPZ`, or put `mkxp-z`
  on your `PATH`.
- **`make mkxp` fails to download a dependency**: `lib/mkxp-z/linux/Makefile`
  downloads its dependencies from GitHub, gitlab.freedesktop.org and
  ftp.gnu.org. If some of these are unreachable, install the matching system
  `-dev` packages (pixman, uchardet, dbus, iconv come with most distros), build
  the remaining targets with `make -C lib/mkxp-z/linux <target>`, and run
  `SKIP_DEPS=1 make mkxp`.
- **`make mkxp` fails with "executable host ruby is required"**: building
  Ruby 3.1 from source needs an installed Ruby. Install one (`ruby -v` should
  work in the same terminal), then run `make mkxp` again. `build_engine.sh`
  passes it to Ruby's build with `--with-baseruby` and re-configures a Ruby
  tree that was configured without one.
- **`make mkxp` fails with "RPC failed", "Connection reset by peer" or
  "early EOF"**: a download was interrupted. Dependencies are cloned
  shallowly (`--depth 1`) and the dependency build is retried automatically
  (`DEPS_RETRIES`, default 3). If it still fails, run `make mkxp` again; it
  continues where it stopped.
- **`make mkxp` sits for a long time after a "detached HEAD" message**:
  dependency downloads print nothing while they run. Older versions also
  downloaded FluidSynth's ~570 MB test data, which the build never uses;
  `build_engine.sh` now fetches FluidSynth without it. If an older run is
  stuck there, press Ctrl-C and run `make mkxp` again; it repairs a partly
  downloaded FluidSynth folder and continues.
- **`downloads/` or `build-x86_64/` at the repository root**: left over from
  an earlier version of `build_engine.sh` that ran the dependency build in the
  wrong folder. Delete them; the dependencies now build in `lib/mkxp-z/linux/`.
- **No sound / "Could not detect an available audio device"**: on machines
  without audio, set `ALSOFT_DRIVERS=null` (done automatically for
  `--compile`).
- **Blurry or clipped text**: keep the font sizes in `MessageConfig` at 16/13/16
  and `"fontHeightReporting": 1`. Other sizes are not pixel-aligned.
- **A graphic looks rough**: check `build/resize_report.txt`. It's probably art
  that wasn't a clean 2× upscale. Draw a 1× version in `src/assets/graphics/`.
- **Script calls in events use 512×384 coordinates**: `halve_data.rb` can't
  convert Ruby code inside event script commands. Halve those numbers by hand.
