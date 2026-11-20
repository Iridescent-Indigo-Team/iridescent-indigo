#===============================================================================
# Pokessentials build
#-------------------------------------------------------------------------------
# `make` turns the sources in src/ into a runnable game folder in build/:
#   src/data/            -> build/Scripts/   (run by build/loader.rb)
#   src/loader.rb        -> build/loader.rb
#   src/mkxp.json        -> build/mkxp.json
#   src/Game.ini         -> build/Game.ini
#   src/assets/graphics  -> build/Graphics/  (halved to 256x192 scale)
#   src/assets/audio     -> build/Audio/
#   src/assets/fonts     -> build/Fonts/
#   src/pbs/ (JSON)      -> build/PBS/       (exported by tools/importer/pbs;
#                                             src/assets/pbs is copied
#                                             instead until src/pbs exists)
#   src/assets/data      -> build/Data/      (pixel values halved)
#   src/tiled/ (Tiled)   -> build/Data/Map*.rxdata, MapInfos, Tilesets,
#                           CommonEvents, System, atmospheres.dat and the
#                           map datasets of build/PBS (compiled by
#                           tools/importer/tiled once src/tiled has a map
#                           registry; see docs/TILED.md)
#   src/assets/plugins   -> build/Plugins/
#   src/assets/locales   -> build/Data/messages_<lang>_*.dat and
#                           build/Graphics/Locales/<lang>/ (translations,
#                           validated and compiled by tools/importer/locales)
#
# See docs/BUILDING.md for the full guide. Run `make help` for the targets.
#===============================================================================

BUILD     ?= build
DIST      ?= dist
SRC       := src
ASSETS    := $(SRC)/assets
SCRIPTS   := tools/scripts
PYTHON    ?= python3
RUBY      ?= ruby
JOBS      ?= $(shell nproc 2>/dev/null || echo 4)
ANDROID_PACKAGE ?= com.mkxpz
GAME_NAME ?= pokessentials

SYNC      := $(PYTHON) -I $(SCRIPTS)/sync_dir.py
PBS_JSON  := $(PYTHON) -I tools/importer/pbs/pbs_json.py
PBS_SRC   := $(SRC)/pbs
PBS_SCHEMA := tools/importer/pbs/engine_schema.json
FORCE     ?= 0
LOCALES   := $(PYTHON) -I tools/importer/locales/locales.py
# LANGS=de,fr limits the locale targets to some languages; STRICT=1 makes
# translation warnings fail the build too.
LANGS     ?=
STRICT    ?= 0
LOCALE_ARGS = $(if $(LANGS),--lang $(LANGS))
# Tiled: src/tiled is in use once it has a map registry.
TILED     := $(PYTHON) -I tools/importer/tiled/tiled_compiler.py --ruby $(RUBY)
TILED_SRC := $(SRC)/tiled
TILED_ON  := $(wildcard $(TILED_SRC)/maps/registry.json)
TILED_PBS := $(BUILD)/.tiled/pbs
# Datasets the Tiled maps own (left alone by pull-pbs).
TILED_DATASETS := map_metadata,encounters,map_connections

.PHONY: all build scripts graphics audio fonts pbs data plugins config \
        run debug release live compile pull-pbs import-pbs validate-pbs \
        pbs-schema test-pbs ground-battlers test-ground-battlers locales update-locales validate-locales test-locales \
        tiled validate-tiled import-rxdata tiled-assets tiled-project tiled-text \
        export-events import-events export-tiledata import-tiledata test-tiled \
        mkxp desktop android apk \
        install-assets uninstall-assets clean clean-data distclean help

all: build

## build: build the whole game folder in build/ (default)
build: scripts graphics audio fonts tiled pbs data plugins config locales
	@echo "Built $(BUILD)/. Run ./game.sh to play."

## scripts: copy src/data to build/Scripts
scripts:
	@$(SYNC) --delete $(SRC)/data $(BUILD)/Scripts

## graphics: halve src/assets/graphics into build/Graphics (incremental)
graphics:
	@$(PYTHON) -I $(SCRIPTS)/resize_graphics.py $(ASSETS)/graphics $(BUILD)/Graphics \
		--jobs $(JOBS) --report $(BUILD)/resize_report.txt --keep Tilesets/Tiled

## audio: copy src/assets/audio to build/Audio
audio:
	@$(SYNC) --delete $(ASSETS)/audio $(BUILD)/Audio

## fonts: copy src/assets/fonts to build/Fonts
fonts:
	@$(SYNC) --delete $(ASSETS)/fonts $(BUILD)/Fonts

# The JSON in src/pbs is the source of the PBS files: `make pbs` validates it
# and writes build/PBS/*.txt. The in-game debug editors write to build/PBS;
# `make pull-pbs` imports their changes back into src/pbs. An export never
# overwrites a PBS file changed since the last export (pull it first, or use
# FORCE=1). Until src/pbs exists, src/assets/pbs is copied as before.
## pbs: export the JSON in src/pbs to build/PBS (validates it first)
pbs: $(if $(TILED_ON),tiled)
	@if [ -n "$(TILED_ON)" ]; then \
		$(PBS_JSON) --src $(TILED_PBS) export $(BUILD)/PBS $(if $(filter 1,$(FORCE)),--force); \
	elif [ -d $(PBS_SRC) ]; then \
		$(PBS_JSON) --src $(PBS_SRC) export $(BUILD)/PBS $(if $(filter 1,$(FORCE)),--force); \
	else \
		$(SYNC) --update $(ASSETS)/pbs $(BUILD)/PBS; \
	fi

## import-pbs: import src/assets/pbs (top-level files only) into the JSON in src/pbs
import-pbs:
	@$(PBS_JSON) --src $(PBS_SRC) import $(ASSETS)/pbs

## pull-pbs: import PBS files changed by the debug editors (build/PBS) into src/pbs
pull-pbs:
	@$(PBS_JSON) --src $(PBS_SRC) import $(BUILD)/PBS $(if $(TILED_ON),--skip $(TILED_DATASETS))

## validate-pbs: check the JSON in src/pbs
validate-pbs:
	@$(PBS_JSON) --src $(if $(TILED_ON),$(TILED_PBS),$(PBS_SRC)) validate

## pbs-schema: dump the PBS schemas from the engine into tools/importer/pbs
pbs-schema: scripts plugins config
	@./game.sh --no-build --dump-schema $(PBS_SCHEMA)
	@if [ -d $(PBS_SRC) ]; then $(PBS_JSON) --src $(PBS_SRC) schema; fi

## test-pbs: run the PBS <-> JSON converter's tests
test-pbs:
	@$(PYTHON) -I -m unittest discover -s tools/importer/pbs/tests -t tools/importer/pbs

# Battle sprite metrics: stand every Pokémon's feet on the ground lines (see
# docs/BUILDING.md#battler-positions). ARGS passes options to the tool, e.g.
# ARGS=--check or ARGS="--species PIKACHU --verbose".
## ground-battlers: recalculate the y metrics in src/pbs/pokemon_metrics from the sprites
ground-battlers:
	@$(PYTHON) -I $(SCRIPTS)/ground_battlers.py --new-forms $(ARGS)

## test-ground-battlers: run the battler grounding tool's tests
test-ground-battlers:
	@$(PYTHON) -I -m unittest discover -s $(SCRIPTS)/tests -t $(SCRIPTS)

# Translations: one folder of CSVs per language in src/assets/locales (see
# docs/LOCALIZATION.md). `make locales` validates them and compiles them into
# the message files the game loads; errors stop the build, warnings don't
# (unless STRICT=1).
## locales: validate the translations and compile them into build/Data
locales: data
	@$(LOCALES) $(LOCALE_ARGS) build $(BUILD) $(if $(filter 1,$(STRICT)),--strict)

## update-locales: write the current English text into every language's CSVs
update-locales: $(if $(TILED_ON),tiled)
	@$(LOCALES) $(LOCALE_ARGS) update

## validate-locales: check the translations (VERBOSE=1 lists every warning)
validate-locales: $(if $(TILED_ON),tiled)
	@$(LOCALES) $(LOCALE_ARGS) validate $(if $(filter 1,$(STRICT)),--strict) $(if $(filter 1,$(VERBOSE)),--verbose)

## test-locales: run the localization tools' tests
test-locales:
	@$(PYTHON) -I -m unittest discover -s tools/importer/locales/tests -t tools/importer/locales

## data: copy src/assets/data to build/Data, halving pixel values
data:
	@mkdir -p $(BUILD)/Data
	@$(RUBY) $(SCRIPTS)/halve_data.rb $(ASSETS)/data $(BUILD)/Data \
		$(if $(TILED_ON),--skip-list $(BUILD)/.tiled/owned.txt)

# Tiled (see docs/TILED.md). Once src/tiled/maps/registry.json exists, maps,
# tilesets, events, common events, system data, map metadata, encounters,
# connections and atmospheres are compiled from src/tiled on every build.
# STRICT=1 makes warnings fail too; FORCE=1 rebuilds everything.
## tiled: compile src/tiled into build/ (does nothing until a map registry exists)
tiled:
	@if [ -n "$(TILED_ON)" ]; then \
		$(TILED) build --build $(BUILD) $(if $(filter 1,$(FORCE)),--force) $(if $(filter 1,$(STRICT)),--strict); \
	fi

## validate-tiled: check src/tiled (maps, tilesets, events, scripts) without building
validate-tiled:
	@$(TILED) validate $(if $(filter 1,$(STRICT)),--strict)

## import-rxdata: import RPG Maker XP data (src/assets/data, or DATA=dir) into src/tiled
import-rxdata:
	@$(TILED) import $(or $(DATA),$(ASSETS)/data) $(if $(filter 1,$(FORCE)),--force)
	@$(TILED) autotiles
	@-$(TILED) previews

## tiled-assets: regenerate autotile tilesets, event previews and the Tiled project types
tiled-assets:
	@$(TILED) autotiles $(if $(filter 1,$(ALL)),--all)
	@-$(TILED) previews
	@$(TILED) project

## tiled-project: regenerate the custom types in src/tiled/pokessentials.tiled-project
tiled-project:
	@$(TILED) project

## tiled-text: write every message of the compiled maps to build/tiled_text.csv
tiled-text: tiled
	@$(TILED) text --build $(BUILD)

## export-events: write MAP's events as standalone .rb files into OUT (MAP=id/name OUT=dir)
export-events:
	@$(TILED) export-events "$(MAP)" "$(or $(OUT),build/events)"

## import-events: add standalone event .rb files (FILES=...) to MAP
import-events:
	@$(TILED) import-events "$(MAP)" $(FILES)

## export-tiledata: write TILESET's tile data to OUT (.json or .csv)
export-tiledata:
	@$(TILED) export-tiledata "$(TILESET)" "$(OUT)"

## import-tiledata: read tile data into TILESET from FILE (.json/.csv, or Tilesets.rxdata with ID=n)
import-tiledata:
	@$(TILED) import-tiledata "$(TILESET)" "$(FILE)" $(if $(ID),--tileset-id $(ID))

## test-tiled: run the Tiled tools' tests
test-tiled:
	@$(PYTHON) -I -m unittest discover -s tools/importer/tiled/tests -t tools/importer/tiled

## plugins: copy src/assets/plugins to build/Plugins
plugins:
	@$(SYNC) --delete $(ASSETS)/plugins $(BUILD)/Plugins

## config: copy the loader, mkxp.json and Game.ini into build/
config:
	@mkdir -p $(BUILD)
	@cp $(SRC)/loader.rb $(SRC)/mkxp.json $(SRC)/Game.ini $(BUILD)/

## run: build and play (debug mode)
run:
	@./game.sh

## debug: same as run
debug: run

## release: build and play without debug mode
release:
	@./game.sh --release

## live: play using the scripts in src/data directly (no script copy)
live:
	@./game.sh --live

## compile: compile PBS into build/Data/*.dat headlessly, then exit
compile: build
	@./game.sh --no-build --compile

## mkxp: build the mkxp-z engine from lib/mkxp-z into build/engine
mkxp:
	@$(SCRIPTS)/build_engine.sh $(BUILD)/engine

## desktop: package build/, the engine and play.sh into dist/<name>-linux.tar.gz
desktop: compile
	@test -x $(BUILD)/engine/mkxp-z || { echo "No engine in $(BUILD)/engine; run 'make mkxp' first."; exit 1; }
	@mkdir -p $(DIST)
	@cp $(SCRIPTS)/play.sh $(BUILD)/play.sh
	@tar -czf $(DIST)/$(GAME_NAME)-linux.tar.gz --exclude=.essentials --exclude=.engine-build \
		--exclude=resize_report.txt --exclude=errorlog.txt \
		--transform 's|^$(BUILD)|$(GAME_NAME)|' $(BUILD)
	@echo "Wrote $(DIST)/$(GAME_NAME)-linux.tar.gz"

## android: package build/ as a game archive for the mkxp-z Android app
android: compile
	@mkdir -p $(DIST)
	@rm -f $(DIST)/$(GAME_NAME)-android.zip
	@cd $(BUILD) && zip -qr -X ../$(DIST)/$(GAME_NAME)-android.zip . \
		-x 'engine/*' -x '.engine-build/*' -x '.essentials/*' -x 'resize_report.txt' \
		-x 'errorlog.txt' -x '.compile_ok' -x 'play.sh'
	@cp $(DIST)/$(GAME_NAME)-android.zip $(DIST)/main.1.$(ANDROID_PACKAGE).obb
	@echo "Wrote $(DIST)/$(GAME_NAME)-android.zip and $(DIST)/main.1.$(ANDROID_PACKAGE).obb"

## apk: build the mkxp-z Android app (needs ANDROID_NDK_HOME and the Android SDK)
apk:
	@$(SCRIPTS)/build_apk.sh $(DIST)

## install-assets: copy Essentials graphics/audio/PBS/data into src/assets
install-assets:
	@$(SCRIPTS)/install_assets.sh

## uninstall-assets: remove the files install-assets copied
uninstall-assets:
	@$(SCRIPTS)/uninstall_assets.sh

## clean-data: remove compiled PBS data (recompiled on next launch)
clean-data:
	@$(SCRIPTS)/clean_data.sh

## clean: remove build/ except the built engine
clean:
	@find $(BUILD) -mindepth 1 -maxdepth 1 ! -name engine -exec rm -rf {} + 2>/dev/null || true
	@echo "Cleaned $(BUILD)/ (kept $(BUILD)/engine)."

## distclean: remove build/ and dist/ entirely
distclean:
	@rm -rf $(BUILD) $(DIST)
	@echo "Removed $(BUILD)/ and $(DIST)/."

## help: list the targets
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  /'
