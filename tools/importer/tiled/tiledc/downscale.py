"""@package tiledc.downscale
One-time conversion of a src/tiled made for 2x (32px tile) graphics to the 1x
(16px tile) graphics Pokessentials keeps in src/assets.

Older versions kept Essentials' 2x art in src/assets/graphics and halved it on
every build, so src/tiled used 32px tiles and 2x pixel values, which the
compiler halved too. Now the sources are 1x and the build copies them as they
are, so every pixel value in src/tiled is halved once:

  * maps (.tmj): tile size, object positions and sizes (and polygon points),
    layer offsets, parallax origin, and the scroll_x/scroll_y properties of
    atmosphere image layers;
  * tilesets (.tsj, autotiles included): tile size, image size, margin,
    spacing, tile offset, grid, image sizes of image-collection tiles, and
    the objects of tile collision shapes;
  * object templates (.tx): object position and size;
  * the world file (.world): map positions and sizes;
  * atmosphere groups (atmospheres/*.json): scroll_x/y and offset_x/y;
  * event scripts (events/, common_events/, templates/events/): the x and y
    of show_picture and move_picture commands with constant coordinates
    (show_picture_variables / move_picture_variables hold variable numbers
    and are left alone), exactly as halve_data.rb halves Show/Move Picture.

Pixel values are halved like halve_data.rb does (halves rounded away from
zero); odd values are listed, since they lose half a pixel. The generated
folder (event previews) is skipped: `make tiled-assets` recreates it.

The conversion only runs when the maps and tilesets still use 32px tiles, so
running it again does nothing.
"""

import glob
import math
import os
import re

from . import config
from .problems import TiledError
from .tiledio import load_json, save_json

## Tile size of the old 2x sources.
OLD_TILE = 32


def half(value):
    """Halves a pixel value like HalveData.half (halves rounded away from zero
    for integers; floats stay exact)."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return value
    if isinstance(value, float):
        return value / 2.0
    return int(math.copysign(math.floor(abs(value) / 2.0 + 0.5), value))


class Converter:
    """Halves the pixel values of one src/tiled folder."""

    def __init__(self, paths, log=print):
        self.paths = paths
        self.log = log
        ## Messages about odd values (they lose half a pixel).
        self.odd = []
        ## Files written.
        self.changed = 0

    # --------------------------------------------------------------------- utils
    def _half_keys(self, obj, keys, where):
        """Halves obj[key] for every key present."""
        for k in keys:
            if k in obj:
                v = obj[k]
                if isinstance(v, int) and not isinstance(v, bool) and v % 2:
                    self.odd.append("%s: %s = %d" % (where, k, v))
                obj[k] = half(v)

    def _save(self, path, data):
        """Writes a JSON file in the tools' layout, counting it if it changed."""
        if save_json(path, data):
            self.changed += 1

    # ---------------------------------------------------------------- detection
    def tile_sizes(self):
        """Tile sizes of every map and tileset: {path: (w, h)}."""
        sizes = {}
        for path in self.map_files() + self.tileset_files():
            data = load_json(path)
            sizes[path] = (data.get("tilewidth"), data.get("tileheight"))
        return sizes

    def needed(self):
        """True if src/tiled still uses 32px tiles.

        @throws TiledError if some files use 32px tiles and others don't
        """
        sizes = self.tile_sizes()
        old = [p for p, s in sizes.items() if s == (OLD_TILE, OLD_TILE)]
        if not old:
            return False
        new = [p for p, s in sizes.items() if s == (config.TILE, config.TILE)]
        if new:
            raise TiledError("%s mixes %dpx tiles (e.g. %s) and %dpx tiles (e.g. %s); convert or fix them "
                             "by hand first" % (self.paths.rel(self.paths.src), OLD_TILE, self.paths.rel(old[0]),
                                                config.TILE, self.paths.rel(new[0])))
        return True

    def map_files(self):
        """@return every .tmj map"""
        return sorted(glob.glob(os.path.join(self.paths.maps, "**", "*.tmj"), recursive=True))

    def tileset_files(self):
        """@return every .tsj tileset (autotiles too), except generated ones"""
        generated = os.path.normcase(self.paths.generated) + os.sep
        return sorted(p for p in glob.glob(os.path.join(self.paths.src, "**", "*.tsj"), recursive=True)
                      if not os.path.normcase(p).startswith(generated))

    # ------------------------------------------------------------------- objects
    def _object(self, obj, where):
        """Halves an object's position and size, and its polygon points."""
        self._half_keys(obj, ("x", "y", "width", "height"), where)
        for key in ("polygon", "polyline"):
            for point in obj.get(key) or []:
                self._half_keys(point, ("x", "y"), where + " " + key)

    def _layers(self, layers, where):
        """Halves the pixel values of map layers (group layers included)."""
        for layer in layers or []:
            lw = "%s layer %r" % (where, layer.get("name"))
            self._half_keys(layer, ("offsetx", "offsety"), lw)
            for obj in layer.get("objects") or []:
                self._object(obj, "%s object %s" % (lw, obj.get("id")))
            if layer.get("type") == "imagelayer":
                for p in layer.get("properties") or []:
                    if p.get("name") in ("scroll_x", "scroll_y"):
                        self._half_keys(p, ("value",), lw + " " + p["name"])
            if layer.get("type") == "group":
                self._layers(layer.get("layers"), where)

    # --------------------------------------------------------------------- files
    def convert_map(self, path):
        """A .tmj map: tile size and every pixel value."""
        data = load_json(path)
        where = self.paths.rel(path)
        data["tilewidth"] = config.TILE
        data["tileheight"] = config.TILE
        self._half_keys(data, ("parallaxoriginx", "parallaxoriginy"), where)
        self._layers(data.get("layers"), where)
        self._save(path, data)

    def convert_tileset(self, path):
        """A .tsj tileset (regular or autotile)."""
        data = load_json(path)
        where = self.paths.rel(path)
        self._half_keys(data, ("tilewidth", "tileheight", "imagewidth", "imageheight", "margin", "spacing"),
                        where)
        if isinstance(data.get("tileoffset"), dict):
            self._half_keys(data["tileoffset"], ("x", "y"), where + " tileoffset")
        if isinstance(data.get("grid"), dict) and data["grid"].get("width", 1) > 1:
            self._half_keys(data["grid"], ("width", "height"), where + " grid")
        for tile in data.get("tiles") or []:
            tw = "%s tile %s" % (where, tile.get("id"))
            self._half_keys(tile, ("imagewidth", "imageheight", "x", "y", "width", "height"), tw)
            group = tile.get("objectgroup")
            if group:
                for obj in group.get("objects") or []:
                    self._object(obj, tw)
        self._save(path, data)

    def convert_template(self, path):
        """A .tx object template."""
        data = load_json(path)
        if isinstance(data.get("object"), dict):
            self._object(data["object"], self.paths.rel(path))
        self._save(path, data)

    def convert_world(self, path):
        """The .world file placing maps next to each other."""
        data = load_json(path)
        for m in data.get("maps") or []:
            self._half_keys(m, ("x", "y", "width", "height"), "%s %s" % (self.paths.rel(path), m.get("fileName")))
        self._save(path, data)

    def convert_atmosphere(self, path):
        """An atmosphere group (atmospheres/<id>.json)."""
        data = load_json(path)
        for i, layer in enumerate(data.get("layers") or []):
            self._half_keys(layer, ("scroll_x", "scroll_y", "offset_x", "offset_y"),
                            "%s layers[%d]" % (self.paths.rel(path), i))
        self._save(path, data)

    def convert_script(self, path):
        """An event script: halves its Show/Move Picture coordinates."""
        with open(path, encoding="utf-8") as f:
            text = f.read()
        new = halve_picture_commands(text, self.odd, self.paths.rel(path))
        if new != text:
            tmp = path + ".tmp"
            with open(tmp, "w", encoding="utf-8", newline="") as f:
                f.write(new)
            os.replace(tmp, path)
            self.changed += 1

    def script_files(self):
        """@return every event script (maps, common events and templates)"""
        files = []
        for folder in (self.paths.events, self.paths.common_events, os.path.join(self.paths.templates, "events")):
            files += glob.glob(os.path.join(folder, "**", "*.rb"), recursive=True)
        return sorted(set(files))

    def run(self):
        """Converts everything. @return True if a conversion was needed"""
        if not self.needed():
            return False
        for path in self.map_files():
            self.convert_map(path)
        for path in self.tileset_files():
            self.convert_tileset(path)
        for path in sorted(glob.glob(os.path.join(self.paths.templates, "**", "*.tx"), recursive=True)):
            self.convert_template(path)
        for path in sorted(glob.glob(os.path.join(self.paths.maps, "**", "*.world"), recursive=True)):
            self.convert_world(path)
        if os.path.isdir(self.paths.atmospheres):
            for path in sorted(glob.glob(os.path.join(self.paths.atmospheres, "*.json"))):
                self.convert_atmosphere(path)
        for path in self.script_files():
            self.convert_script(path)
        return True


## Start of a show/move picture command with constant coordinates.
PICTURE_CALL = re.compile(r"\b(?:show|move)_picture\(")
## An x: or y: keyword argument with an integer value.
COORD_ARG = re.compile(r"(?<![\w@$])([xy]):(\s*)(-?\d+)(?![\w.])")


def _call_spans(text, start):
    """Splits the arguments of the call opened at text[start - 1].

    @return (end, spans): end is the index just past the closing parenthesis
      (-1 if there is none), spans the (begin, end) ranges of the code between
      strings and comments, where keyword arguments can be
    """
    depth = 1
    i = start
    quote = None
    spans = []
    code_start = start
    while i < len(text):
        c = text[i]
        if quote:
            if c == "\\":
                i += 2
                continue
            if c == quote:
                quote = None
                code_start = i + 1
        elif c in "\"'":
            quote = c
            spans.append((code_start, i))
        elif c == "#":
            spans.append((code_start, i))
            nl = text.find("\n", i)
            i = len(text) if nl < 0 else nl
            code_start = i
            continue
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                spans.append((code_start, i))
                return i + 1, spans
        i += 1
    return -1, spans


def halve_picture_commands(text, odd=None, where=""):
    """Halves the constant x/y of every show_picture/move_picture call in an
    event script.

    @param odd list that collects messages about odd values (optional)
    @return the new text
    """
    out = []
    pos = 0
    for m in PICTURE_CALL.finditer(text):
        if m.start() < pos:
            continue
        end, spans = _call_spans(text, m.end())
        if end < 0:
            break

        def repl(cm):
            value = int(cm.group(3))
            if value % 2 and odd is not None:
                line = text.count("\n", 0, m.start()) + 1
                odd.append("%s:%d: %s = %d" % (where, line, cm.group(1), value))
            return "%s:%s%d" % (cm.group(1), cm.group(2), half(value))

        out.append(text[pos:m.end()])
        last = m.end()
        for begin, stop in spans:
            out.append(text[last:begin])
            out.append(COORD_ARG.sub(repl, text[begin:stop]))
            last = stop
        out.append(text[last:end])
        pos = end
    out.append(text[pos:])
    return "".join(out)


def downscale(paths, log=print):
    """Converts a 32px src/tiled to 16px. @return True if it was converted"""
    conv = Converter(paths, log)
    if not conv.run():
        log("%s already uses %dpx tiles; nothing to convert." % (paths.rel(paths.src), config.TILE))
        return False
    log("Converted %s to %dpx tiles (%d files changed)." % (paths.rel(paths.src), config.TILE, conv.changed))
    if conv.odd:
        log("%d odd pixel values were rounded (half a pixel lost):" % len(conv.odd))
        for msg in conv.odd[:50]:
            log("  " + msg)
        if len(conv.odd) > 50:
            log("  ... and %d more" % (len(conv.odd) - 50))
    return True
