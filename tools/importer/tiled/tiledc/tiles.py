"""@package tiledc.tiles
Tile data (passage, priority, terrain tag, bush, counter) stored on Tiled
tilesets, and the combined RMXP tilesets the compiler builds from them.

Tile data lives in a custom class property "TileData" on each tile of a .tsj
(or on the tileset itself, as the default for all its tiles; autotiles use
that). Tiles without it are passable, priority 0, terrain tag None.
"""

import os

from . import config
from .config import (PASSAGE_BUSH, PASSAGE_COUNTER, PASSAGE_DOWN, PASSAGE_KNOWN, PASSAGE_LEFT,
                     PASSAGE_RIGHT, PASSAGE_UP, TILESET_COLUMNS, TILESET_START_ID, AUTOTILE_TILES)
from .problems import TiledError
from .tiledio import image_path, load_json, make_prop, props, save_json, tiles_by_id

## Name of the tile data class property.
TILE_DATA = "TileData"
## Default tile data.
DEFAULT_TILE_DATA = {"block_down": False, "block_left": False, "block_right": False,
                     "block_up": False, "bush": False, "counter": False, "priority": 0,
                     "terrain_tag": "None", "extra_passage": 0}


class TerrainTags:
    """Terrain tag names <-> numbers."""

    def __init__(self, pairs=None):
        pairs = pairs if pairs is not None else config.terrain_tags()
        ## Number -> name.
        self.names = {n: name for n, name in pairs}
        ## Name -> number.
        self.numbers = {name: n for n, name in pairs}

    def name(self, number):
        return self.names.get(number, "Tag%d" % number)

    def number(self, name):
        """@return the number, or None if the name is unknown"""
        if name in (None, ""):
            return 0
        if name in self.numbers:
            return self.numbers[name]
        if isinstance(name, int):
            return name
        if str(name).startswith("Tag") and str(name)[3:].isdigit():
            return int(str(name)[3:])
        return None


def to_tile_data(passage, priority, tag, tags):
    """RMXP values -> TileData dict (only non-default members)."""
    data = {}
    if passage & PASSAGE_DOWN:
        data["block_down"] = True
    if passage & PASSAGE_LEFT:
        data["block_left"] = True
    if passage & PASSAGE_RIGHT:
        data["block_right"] = True
    if passage & PASSAGE_UP:
        data["block_up"] = True
    if passage & PASSAGE_BUSH:
        data["bush"] = True
    if passage & PASSAGE_COUNTER:
        data["counter"] = True
    if passage & ~PASSAGE_KNOWN:
        data["extra_passage"] = passage & ~PASSAGE_KNOWN
    if priority:
        data["priority"] = priority
    if tag:
        data["terrain_tag"] = tags.name(tag)
    return data


def from_tile_data(data, tags):
    """TileData dict -> (passage, priority, terrain tag number or None if unknown)."""
    d = dict(DEFAULT_TILE_DATA)
    d.update(data or {})
    passage = int(d.get("extra_passage") or 0)
    for key, bit in (("block_down", PASSAGE_DOWN), ("block_left", PASSAGE_LEFT),
                     ("block_right", PASSAGE_RIGHT), ("block_up", PASSAGE_UP),
                     ("bush", PASSAGE_BUSH), ("counter", PASSAGE_COUNTER)):
        if d.get(key):
            passage |= bit
    return passage, int(d.get("priority") or 0), tags.number(d.get("terrain_tag"))


def tile_data_prop(data):
    """The TileData property entry for a dict of members."""
    return make_prop(TILE_DATA, data, "class", TILE_DATA)


class TilesetInfo:
    """One Tiled tileset (.tsj) as the compiler sees it."""

    def __init__(self, path, data=None):
        ## Absolute path of the .tsj.
        self.path = os.path.abspath(path)
        ## Tileset JSON.
        self.data = data if data is not None else load_json(path)
        ## "tileset", "autotile" or "preview".
        cls = self.data.get("class", self.data.get("type", ""))
        if cls == config.CLASS_AUTOTILE:
            self.kind = "autotile"
        elif cls == config.CLASS_PREVIEW:
            self.kind = "preview"
        else:
            self.kind = "tileset"
        self._tiles = tiles_by_id(self.data)
        self._default = props(self.data).get(TILE_DATA) or {}

    @property
    def name(self):
        return self.data.get("name") or os.path.splitext(os.path.basename(self.path))[0]

    @property
    def columns(self):
        return self.data.get("columns", 0)

    @property
    def tilecount(self):
        return self.data.get("tilecount", 0)

    @property
    def rows(self):
        """Rows of 8 tiles this tileset adds to a combined RMXP tileset."""
        return (self.tilecount + TILESET_COLUMNS - 1) // TILESET_COLUMNS

    def image(self):
        """Absolute path of the tileset image."""
        return image_path(self.data, self.path)

    def autotile_name(self):
        """Name of the RMXP autotile graphic (in Graphics/Autotiles)."""
        return props(self.data).get("autotile") or self.name

    def tile_data(self, local_id):
        """TileData members of a tile (tileset default merged with the tile's own)."""
        data = dict(self._default)
        tile = self._tiles.get(local_id)
        if tile:
            data.update(props(tile).get(TILE_DATA) or {})
        return data

    def has_tile_data(self):
        """@return True if any tile (or the tileset) has TileData"""
        if self._default:
            return True
        return any(TILE_DATA in props(t) for t in self._tiles.values())


#===============================================================================
# Combined RMXP tilesets
#===============================================================================
class TilesetRegistry:
    """Stable RMXP tileset ids for each combination of Tiled tilesets
    (src/tiled/tilesets/registry.json).

    Format:
    @code
    {"tilesets": [{"id": 1, "name": "Outside",
                   "tilesets": ["outside.tsj"], "autotiles": ["autotiles/sea.tsj"]}]}
    @endcode
    Paths are relative to src/tiled/tilesets. New combinations get the next id
    when the compiler first sees them; commit the file to keep ids stable
    (dungeon_tilesets.txt and plugins refer to tileset ids).
    """

    def __init__(self, path):
        ## Registry file.
        self.path = path
        ## Entries.
        self.entries = []
        if os.path.isfile(path):
            self.entries = load_json(path).get("tilesets", [])
        ## True if entries were added since loading.
        self.changed = False

    def _key(self, regular, autotiles):
        return (tuple(regular), tuple(autotiles))

    def find(self, regular, autotiles):
        key = self._key(regular, autotiles)
        for e in self.entries:
            if self._key(e.get("tilesets", []), e.get("autotiles", [])) == key:
                return e
        return None

    def get(self, regular, autotiles, name):
        """The entry for a combination, adding it if new."""
        found = self.find(regular, autotiles)
        if found:
            return found
        entry = {"id": max([e["id"] for e in self.entries] + [0]) + 1, "name": name,
                 "tilesets": list(regular), "autotiles": list(autotiles)}
        self.entries.append(entry)
        self.changed = True
        return entry

    def save(self):
        self.entries.sort(key=lambda e: e["id"])
        return save_json(self.path, {"tilesets": self.entries})


class Combined:
    """An RMXP tileset made of several Tiled tilesets.

    RMXP ids: 1-47 unused, 48*(k+1)... autotile k (k < 7), 384 + 8*row + column
    for the regular tilesets, stacked in map order.
    """

    def __init__(self, entry, regular, autotiles):
        ## Registry entry (id, name, ...).
        self.entry = entry
        ## TilesetInfo of each regular tileset, in order.
        self.regular = regular
        ## TilesetInfo of each autotile, in slot order.
        self.autotiles = autotiles
        ## First row of each regular tileset in the combined image.
        self.row_offsets = []
        row = 0
        for ts in regular:
            self.row_offsets.append(row)
            row += ts.rows
        ## Total rows of the combined image.
        self.rows = row

    @property
    def id(self):
        return self.entry["id"]

    @property
    def size(self):
        """Entries in the passage/priority/terrain tables."""
        return TILESET_START_ID + TILESET_COLUMNS * self.rows

    def rmxp_id(self, kind_index, local_id, is_autotile):
        """The RMXP tile id of a Tiled tile.

        @param kind_index index in self.autotiles or self.regular
        """
        if is_autotile:
            return AUTOTILE_TILES * (kind_index + 1) + (local_id % AUTOTILE_TILES)
        return TILESET_START_ID + self.row_offsets[kind_index] * TILESET_COLUMNS + local_id

    def tables(self, tags, problems=None):
        """The passages, priorities and terrain tag tables.

        @return (passages, priorities, terrain_tags) lists
        """
        size = self.size
        passages = [0] * size
        priorities = [0] * size
        terrain = [0] * size
        priorities[0] = 5

        def put(rmxp, data, ts, local):
            p, pr, tag = from_tile_data(data, tags)
            if tag is None:
                if problems is not None:
                    problems.warning(ts.path, "tile %d" % local,
                                     "unknown terrain tag %r (treated as None)" % data.get("terrain_tag"))
                tag = 0
            passages[rmxp], priorities[rmxp], terrain[rmxp] = p, pr, tag

        for k, ts in enumerate(self.autotiles):
            for local in range(AUTOTILE_TILES):
                put(AUTOTILE_TILES * (k + 1) + local, ts.tile_data(local), ts, local)
        for i, ts in enumerate(self.regular):
            for local in range(ts.tilecount):
                put(self.rmxp_id(i, local, False), ts.tile_data(local), ts, local)
        return passages, priorities, terrain

    def graphic_name(self):
        """The tileset_name RMXP uses (relative to Graphics/Tilesets, no
        extension): the original image when there's exactly one 8-column
        tileset whose image is in Graphics/Tilesets, otherwise a generated
        "Tiled/<id>" (tilesets of any width are reflowed into 8 columns)."""
        if len(self.regular) == 1 and self.regular[0].columns == TILESET_COLUMNS and \
                not self.regular[0].data.get("margin") and not self.regular[0].data.get("spacing"):
            img = self.regular[0].image()
            folder = os.path.join(config.GRAPHICS, "Tilesets")
            if img and os.path.normcase(os.path.abspath(img)).startswith(os.path.normcase(folder) + os.sep):
                return os.path.splitext(os.path.relpath(img, folder))[0].replace(os.sep, "/")
        if not self.regular:
            return ""
        return "Tiled/%d" % self.id

    def write_image(self, graphics_out, force=False):
        """Composes the combined image (halved to the build's 16px tiles) into
        <graphics_out>/Tilesets/Tiled/<id>.png when graphic_name() needs one.

        @return the path written, or None
        """
        name = self.graphic_name()
        if not name.startswith("Tiled/"):
            return None
        out = os.path.join(graphics_out, "Tilesets", name + ".png")
        sources = [ts.image() for ts in self.regular]
        missing = [s for s in sources if not s or not os.path.isfile(s)]
        if missing:
            raise TiledError("tileset image(s) not found: %s" % ", ".join(str(m) for m in missing))
        if not force and os.path.isfile(out):
            newest = max(os.path.getmtime(s) for s in sources)
            if os.path.getmtime(out) >= newest:
                return None
        from PIL import Image  # only needed when tilesets are combined
        tile = config.TILE
        canvas = Image.new("RGBA", (TILESET_COLUMNS * tile, max(1, self.rows) * tile), (0, 0, 0, 0))
        for ts, row in zip(self.regular, self.row_offsets):
            with Image.open(ts.image()) as im:
                im = im.convert("RGBA")
                margin = ts.data.get("margin", 0)
                spacing = ts.data.get("spacing", 0)
                cols = max(1, ts.columns)
                for local in range(ts.tilecount):
                    sx = margin + (local % cols) * (tile + spacing)
                    sy = margin + (local // cols) * (tile + spacing)
                    piece = im.crop((sx, sy, sx + tile, sy + tile))
                    dx = (local % TILESET_COLUMNS) * tile
                    dy = (row + local // TILESET_COLUMNS) * tile
                    canvas.paste(piece, (dx, dy))
        half = canvas.resize((canvas.width // 2, canvas.height // 2), Image.NEAREST)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        half.save(out)
        return out

    def ir(self, tags, problems=None):
        """The Tilesets.rxdata entry for the Ruby back end."""
        passages, priorities, terrain = self.tables(tags, problems)
        names = [ts.autotile_name() for ts in self.autotiles]
        names += [""] * (config.AUTOTILE_SLOTS - len(names))
        return {"id": self.id, "name": self.entry.get("name", ""), "tileset_name": self.graphic_name(),
                "autotile_names": names, "panorama_name": "", "panorama_hue": 0, "fog_name": "",
                "fog_hue": 0, "fog_opacity": 64, "fog_blend_type": 0, "fog_zoom": 200, "fog_sx": 0,
                "fog_sy": 0, "battleback_name": "", "passages": passages, "priorities": priorities,
                "terrain_tags": terrain}
