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
#   src/assets/pbs       -> build/PBS/
#   src/assets/data      -> build/Data/      (pixel values halved)
#   src/assets/plugins   -> build/Plugins/
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

.PHONY: all build scripts graphics audio fonts pbs data plugins config \
        run debug release live compile pull-pbs \
        mkxp desktop android apk \
        install-assets uninstall-assets clean clean-data distclean help

all: build

## build: build the whole game folder in build/ (default)
build: scripts graphics audio fonts pbs data plugins config
	@echo "Built $(BUILD)/. Run ./game.sh to play."

## scripts: copy src/data to build/Scripts
scripts:
	@$(SYNC) --delete $(SRC)/data $(BUILD)/Scripts

## graphics: halve src/assets/graphics into build/Graphics (incremental)
graphics:
	@$(PYTHON) -I $(SCRIPTS)/resize_graphics.py $(ASSETS)/graphics $(BUILD)/Graphics \
		--jobs $(JOBS) --report $(BUILD)/resize_report.txt

## audio: copy src/assets/audio to build/Audio
audio:
	@$(SYNC) --delete $(ASSETS)/audio $(BUILD)/Audio

## fonts: copy src/assets/fonts to build/Fonts
fonts:
	@$(SYNC) --delete $(ASSETS)/fonts $(BUILD)/Fonts

# PBS files are copied with --update so edits made by the in-game debug
# editors (which write to build/PBS) are not overwritten. Use `make pull-pbs`
# to copy those edits back into src/assets/pbs.
## pbs: copy src/assets/pbs to build/PBS (keeps newer files in build/)
pbs:
	@$(SYNC) --update $(ASSETS)/pbs $(BUILD)/PBS

## pull-pbs: copy PBS files changed by the debug editors back to src/assets/pbs
pull-pbs:
	@$(SYNC) --update --only '*.txt' $(BUILD)/PBS $(ASSETS)/pbs
	@echo "Copied newer PBS files from $(BUILD)/PBS to $(ASSETS)/pbs."

## data: copy src/assets/data to build/Data, halving pixel values
data:
	@mkdir -p $(BUILD)/Data
	@$(RUBY) $(SCRIPTS)/halve_data.rb $(ASSETS)/data $(BUILD)/Data

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

## desktop: package build/ and the engine into dist/<name>-linux.tar.gz
desktop: compile
	@test -x $(BUILD)/engine/mkxp-z || { echo "No engine in $(BUILD)/engine; run 'make mkxp' first."; exit 1; }
	@mkdir -p $(DIST)
	@tar -czf $(DIST)/$(GAME_NAME)-linux.tar.gz --exclude=.essentials --exclude=resize_report.txt \
		--transform 's|^$(BUILD)|$(GAME_NAME)|' $(BUILD)
	@echo "Wrote $(DIST)/$(GAME_NAME)-linux.tar.gz"

## android: package build/ as a game archive for the mkxp-z Android app
android: compile
	@mkdir -p $(DIST)
	@rm -f $(DIST)/$(GAME_NAME)-android.zip
	@cd $(BUILD) && zip -qr -X ../$(DIST)/$(GAME_NAME)-android.zip . \
		-x 'engine/*' -x '.essentials/*' -x 'resize_report.txt'
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
