"""@package tiledc.tiledio
Reading and writing Tiled's JSON formats (.tmj maps, .tsj tilesets, .world
worlds, .tx templates) and their custom properties.
"""

import base64
import gzip
import json
import os
import struct
import zlib

from .config import GID_FLAGS, TILE
from .problems import TiledError

## Tiled JSON format version written by the tools.
TILED_VERSION = "1.10"
## Tiled version that wrote the files.
TILED_EDITOR_VERSION = "1.10.2"


def load_json(path):
    """Reads a JSON file. @throws TiledError if it's missing or invalid"""
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        raise TiledError("%s doesn't exist." % path)
    except json.JSONDecodeError as e:
        raise TiledError("%s isn't valid JSON: %s" % (path, e))


def _scalar(v):
    return v is None or isinstance(v, (bool, int, float, str))


def _dump(value, level, row=None):
    pad = " " * level
    inner = " " * (level + 1)
    if isinstance(value, dict):
        if not value:
            return "{}"
        width = value.get("width") if value.get("type") == "tilelayer" else None
        items = []
        for k, v in value.items():
            items.append(inner + json.dumps(k, ensure_ascii=False) + ":" +
                         _dump(v, level + 1, width if k == "data" else None))
        return "{\n" + ",\n".join(items) + "\n" + pad + "}"
    if isinstance(value, list):
        if not value:
            return "[]"
        if all(_scalar(v) for v in value):
            if row and len(value) > row:
                rows = [", ".join(json.dumps(v) for v in value[i:i + row]) for i in range(0, len(value), row)]
                return "[\n" + ",\n".join(inner + r for r in rows) + "\n" + pad + "]"
            return "[" + ", ".join(json.dumps(v, ensure_ascii=False) for v in value) + "]"
        return "[\n" + ",\n".join(inner + _dump(v, level + 1) for v in value) + "\n" + pad + "]"
    return json.dumps(value, ensure_ascii=False)


def dumps(value):
    """JSON text close to Tiled's layout (one key per line), with lists of
    numbers on one line and tile layer data one map row per line, so maps
    diff well in git."""
    return _dump(value, 0) + "\n"


def write_if_changed(path, text):
    """Writes text (str or bytes) only if it differs. @return True if written"""
    data = text.encode("utf-8") if isinstance(text, str) else text
    if os.path.isfile(path):
        with open(path, "rb") as f:
            if f.read() == data:
                return False
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, path)
    return True


def save_json(path, value):
    """Writes a JSON value in Tiled's layout. @return True if the file changed"""
    return write_if_changed(path, dumps(value))


#===============================================================================
# Custom properties
#===============================================================================
def props(obj):
    """An object's custom properties as a dict (class properties become dicts).

    @param obj a map, layer, object, tileset or tile (Tiled JSON)
    """
    result = {}
    for p in obj.get("properties", []) or []:
        result[p["name"]] = p.get("value")
    return result


def prop_types(obj):
    """Property name -> (type, propertytype) of an object's custom properties."""
    return {p["name"]: (p.get("type", "string"), p.get("propertytype", ""))
            for p in obj.get("properties", []) or []}


def make_prop(name, value, ptype=None, propertytype=None):
    """One Tiled property entry.

    @param ptype "string", "int", "float", "bool", "color", "file", "object" or
        "class"; guessed from value when None
    @param propertytype the custom type's name, for class and enum properties
    """
    if ptype is None:
        if isinstance(value, bool):
            ptype = "bool"
        elif isinstance(value, int):
            ptype = "int"
        elif isinstance(value, float):
            ptype = "float"
        elif isinstance(value, dict):
            ptype = "class"
        else:
            ptype = "string"
    p = {"name": name, "type": ptype}
    if propertytype:
        p["propertytype"] = propertytype
    p["value"] = value
    return p


def set_props(obj, entries):
    """Replaces or adds properties on an object, keeping the others.

    @param entries list of make_prop() results
    """
    existing = obj.setdefault("properties", [])
    names = {e["name"] for e in entries}
    kept = [p for p in existing if p["name"] not in names]
    obj["properties"] = sorted(kept + list(entries), key=lambda p: p["name"])
    if not obj["properties"]:
        del obj["properties"]


def remove_props(obj, names):
    """Removes properties by name."""
    if "properties" in obj:
        obj["properties"] = [p for p in obj["properties"] if p["name"] not in names]
        if not obj["properties"]:
            del obj["properties"]


#===============================================================================
# Tile layers
#===============================================================================
def layer_gids(layer):
    """The raw gids of a tile layer (flag bits kept), row by row.

    Supports CSV arrays and base64 data (uncompressed, zlib or gzip).
    @throws TiledError for zstd or chunked (infinite) data
    """
    if "chunks" in layer:
        raise TiledError("layer '%s' uses chunks (infinite map)" % layer.get("name"))
    data = layer.get("data", [])
    if isinstance(data, list):
        return [int(g) for g in data]
    raw = base64.b64decode(data)
    compression = layer.get("compression", "")
    if compression == "zlib":
        raw = zlib.decompress(raw)
    elif compression == "gzip":
        raw = gzip.decompress(raw)
    elif compression:
        raise TiledError("layer '%s' uses %s compression; save it as CSV, zlib or gzip"
                         % (layer.get("name"), compression))
    return list(struct.unpack("<%dI" % (len(raw) // 4), raw))


def split_gid(gid):
    """@return (gid without flags, flag bits)"""
    return gid & ~GID_FLAGS & 0xFFFFFFFF, gid & GID_FLAGS


def tile_layer(name, width, height, data, layer_id):
    """A new CSV tile layer."""
    return {"data": data, "height": height, "id": layer_id, "name": name, "opacity": 1,
            "type": "tilelayer", "visible": True, "width": width, "x": 0, "y": 0}


def iter_layers(layers, parents=()):
    """Every layer depth-first, in drawing order (bottom first).

    @return generator of (layer, tuple of parent group layers)
    """
    for layer in layers:
        yield layer, parents
        if layer.get("type") == "group":
            yield from iter_layers(layer.get("layers", []), parents + (layer,))


#===============================================================================
# Tilesets referenced by a map
#===============================================================================
class MapTileset:
    """A tileset as used by one map: its firstgid and its data."""

    def __init__(self, firstgid, source, data):
        ## First gid of the tileset in this map.
        self.firstgid = firstgid
        ## Absolute path of the .tsj (None if embedded).
        self.source = source
        ## The tileset JSON.
        self.data = data

    @property
    def tilecount(self):
        return self.data.get("tilecount", 0)

    def contains(self, gid):
        return self.firstgid <= gid < self.firstgid + max(self.tilecount, 1)


def map_tilesets(map_data, map_path, cache=None):
    """Loads every tileset a map references, sorted by firstgid.

    @param cache dict path -> tileset JSON, shared between maps
    @return list of MapTileset
    """
    cache = {} if cache is None else cache
    result = []
    base = os.path.dirname(os.path.abspath(map_path))
    for entry in map_data.get("tilesets", []):
        if "source" in entry:
            path = os.path.normpath(os.path.join(base, entry["source"]))
            if path not in cache:
                if not os.path.isfile(path) and "generated" in path.split(os.sep):
                    # Event previews are regenerated by `make tiled-assets`;
                    # the compiler doesn't need them.
                    cache[path] = {"class": "CharacterPreview", "tilecount": 1 << 24, "tilewidth": TILE,
                                   "tileheight": TILE, "name": "Event previews"}
                else:
                    cache[path] = load_json(path)
            result.append(MapTileset(entry["firstgid"], path, cache[path]))
        else:
            result.append(MapTileset(entry["firstgid"], None, entry))
    result.sort(key=lambda t: t.firstgid)
    return result


def tileset_for_gid(tilesets, gid):
    """@return the MapTileset holding gid, or None"""
    found = None
    for ts in tilesets:
        if ts.firstgid <= gid:
            found = ts
        else:
            break
    if found is not None and gid - found.firstgid < max(found.tilecount, 1):
        return found
    return None


def tile_entry(tileset, local_id):
    """The "tiles" entry of a local tile id in a tileset, or None."""
    for t in tileset.get("tiles", []) or []:
        if t.get("id") == local_id:
            return t
    return None


def tiles_by_id(tileset):
    """Local tile id -> "tiles" entry."""
    return {t["id"]: t for t in tileset.get("tiles", []) or [] if "id" in t}


def image_path(tileset, tileset_path):
    """Absolute path of a tileset's image (None for image collections)."""
    image = tileset.get("image")
    if not image:
        return None
    return os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(tileset_path)), image))


def relpath(path, start_file):
    """A path relative to the folder of start_file, with forward slashes."""
    return os.path.relpath(path, os.path.dirname(os.path.abspath(start_file))).replace(os.sep, "/")
