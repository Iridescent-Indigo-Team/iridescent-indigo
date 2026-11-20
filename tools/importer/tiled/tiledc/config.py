"""@package tiledc.config
Paths, format constants and the game's enums (read from the engine sources so
they never go out of date).
"""

import json
import os
import re

## The repository root.
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))))))
## Folder of the Ruby helpers.
RUBY_DIR = os.path.join(ROOT, "tools", "importer", "tiled", "ruby")
## Default Tiled source folder.
DEFAULT_SRC = os.path.join(ROOT, "src", "tiled")
## Source graphics (2x size, 32px tiles). The --graphics option changes it.
GRAPHICS = os.path.join(ROOT, "src", "assets", "graphics")
## The PBS JSON tree.
PBS_SRC = os.path.join(ROOT, "src", "pbs")
## The engine's game scripts.
SCRIPTS = os.path.join(ROOT, "src", "data")
## Engine schema used by the PBS tools.
ENGINE_SCHEMA = os.path.join(ROOT, "tools", "importer", "pbs", "engine_schema.json")

## Tile size in the sources, in pixels. The build halves it to 16.
TILE = 32
## RMXP tile layers per map.
RMXP_LAYERS = 3
## Autotile slots per RMXP tileset.
AUTOTILE_SLOTS = 7
## Tiles per expanded autotile.
AUTOTILE_TILES = 48
## First RMXP id of the regular tileset.
TILESET_START_ID = 384
## Columns of an RMXP tileset image.
TILESET_COLUMNS = 8
## Tiled gid flag bits (horizontal, vertical, diagonal flip, hexagonal 120 rotation).
GID_FLAGS = 0xF0000000
## Default RMXP autotile frame duration, in 1/20ths of a second
## (TilemapRenderer::AUTOTILE_FRAME_DURATION).
AUTOTILE_FRAME_DURATION = 5

## Tiled class names used by Pokessentials.
CLASS_EVENT = "Event"
CLASS_SPAWN = "Spawn"
CLASS_AUTOTILE = "Autotile"
CLASS_PREVIEW = "CharacterPreview"
CLASS_ATMOSPHERE_GROUP = "Atmosphere"

## RMXP direction numbers -> names.
DIRECTIONS = {0: "retain", 2: "down", 4: "left", 6: "right", 8: "up"}
## Page trigger names, by RMXP number.
TRIGGERS = ["action", "player_touch", "event_touch", "autorun", "parallel"]
## Move type names, by RMXP number.
MOVE_TYPES = ["fixed", "random", "approach", "custom"]
## Blend type names, by RMXP number.
BLEND_TYPES = ["normal", "add", "subtract"]
## Self switches.
SELF_SWITCHES = ["", "A", "B", "C", "D"]
## Map edges.
SIDES = ["N", "E", "S", "W"]

## RMXP passage bits.
PASSAGE_DOWN = 0x01
PASSAGE_LEFT = 0x02
PASSAGE_RIGHT = 0x04
PASSAGE_UP = 0x08
PASSAGE_BUSH = 0x40
PASSAGE_COUNTER = 0x80
PASSAGE_KNOWN = 0x0F | PASSAGE_BUSH | PASSAGE_COUNTER


def _registered_ids(filename):
    """Ids registered with `:id => :Name` in a hardcoded data script, in order."""
    path = os.path.join(SCRIPTS, "010_Data", "001_Hardcoded data", filename)
    if not os.path.isfile(path):
        return []
    with open(path, encoding="utf-8") as f:
        text = f.read()
    return re.findall(r":id\s*=>\s*:(\w+)", text)


def terrain_tags():
    """Terrain tag names by id number (GameData::TerrainTag).

    @return list of (number, name)
    """
    path = os.path.join(SCRIPTS, "010_Data", "001_Hardcoded data", "011_TerrainTag.rb")
    result = []
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as f:
            text = f.read()
        for block in re.findall(r"register\(\{(.*?)\}\)", text, re.S):
            name = re.search(r":id\s*=>\s*:(\w+)", block)
            number = re.search(r":id_number\s*=>\s*(\d+)", block)
            if name and number:
                result.append((int(number.group(1)), name.group(1)))
    if not result:
        result = [(0, "None")]
    return sorted(result)


def encounter_types():
    """Encounter type ids (GameData::EncounterType), in order."""
    return _registered_ids("013_EncounterType.rb")


def weathers():
    """Overworld weather ids (GameData::Weather)."""
    return _registered_ids("012_Weather.rb") or ["None"]


def environments():
    """Battle environment ids (GameData::Environment)."""
    return _registered_ids("014_Environment.rb") or ["None"]


def map_metadata_schema():
    """The JSON Schema of one map_metadata entry, if the PBS tools generated it.

    @return dict or None
    """
    path = os.path.join(PBS_SRC, "_schema", "map_metadata.entry.schema.json")
    if not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8") as f:
        return json.load(f)


class Paths:
    """Locations inside one Tiled source folder."""

    def __init__(self, src=DEFAULT_SRC):
        ## The Tiled source folder (src/tiled).
        self.src = os.path.abspath(src)
        ## Maps and the registry.
        self.maps = os.path.join(self.src, "maps")
        ## Map registry (ids, names, tree).
        self.registry = os.path.join(self.maps, "registry.json")
        ## World file that places maps next to each other (map connections).
        self.world = os.path.join(self.maps, "pokessentials.world")
        ## Tilesets.
        self.tilesets = os.path.join(self.src, "tilesets")
        ## Converted autotiles.
        self.autotiles = os.path.join(self.tilesets, "autotiles")
        ## Stable RMXP tileset ids for each combination of tilesets.
        self.tileset_registry = os.path.join(self.tilesets, "registry.json")
        ## Event command files, one folder per map.
        self.events = os.path.join(self.src, "events")
        ## Common event files.
        self.common_events = os.path.join(self.src, "common_events")
        ## Object templates and their event files.
        self.templates = os.path.join(self.src, "templates")
        ## Atmosphere groups.
        self.atmospheres = os.path.join(self.src, "atmospheres")
        ## System data (switch/variable names, start position, ...).
        self.system = os.path.join(self.src, "system.json")
        ## The Tiled project.
        self.project = os.path.join(self.src, "pokessentials.tiled-project")
        ## Generated preview images (gitignored).
        self.generated = os.path.join(self.src, "generated")

    def exists(self):
        """@return True if this folder holds a map registry (Tiled is in use)"""
        return os.path.isfile(self.registry)

    def rel(self, path):
        """A path relative to the repository root, for messages."""
        try:
            return os.path.relpath(path, ROOT)
        except ValueError:
            return path
