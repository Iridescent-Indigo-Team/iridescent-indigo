"""@package tiledc.atmosphere
Atmosphere groups (src/tiled/atmospheres/<id>.json) and map atmosphere layers
(image layers inside a Tiled group layer of class or name "Atmosphere"),
compiled into the data the runtime reads (Data/atmospheres.dat).

A group file:
@code
{
 "name": "Forest mist",
 "fade_frames": 20,
 "layers": [
  {"name": "mist", "graphic": "Fogs/Mist", "z": "above", "opacity": 64,
   "parallax_x": 1.0, "parallax_y": 1.0, "scroll_x": 20, "scroll_y": 0,
   "blend": "normal", "hue": 0, "tone": [0, 0, 0, 0], "zoom_x": 100, "zoom_y": 100,
   "frames": 1, "frame_duration": 5, "repeat_x": true, "repeat_y": true}
 ]
}
@endcode
Pixel values (scroll_x/y in pixels per second, offset_x/y) are in the 32px
source scale, like the graphics, and are halved for the build. "graphic" is a
path under Graphics/ without extension: any folder, not just Fogs and
Panoramas.

A map's "atmosphere" property names its group. Maps with the same group share
its layers, so they continue seamlessly between those maps.
"""

import os

from . import config
from .config import BLEND_TYPES, CLASS_ATMOSPHERE_GROUP
from .tiledio import iter_layers, load_json, props

## Layer settings and their defaults (source scale).
LAYER_DEFAULTS = {
    "graphic": "", "z": "above", "parallax_x": 1.0, "parallax_y": 1.0, "scroll_x": 0.0,
    "scroll_y": 0.0, "offset_x": 0, "offset_y": 0, "opacity": 255, "blend": "normal", "hue": 0,
    "tone": [0, 0, 0, 0], "zoom_x": 100, "zoom_y": 100, "frames": 1, "frame_duration": 5,
    "repeat_x": True, "repeat_y": True, "visible": True,
}
## Largest atmosphere graphic the game draws (Settings::ATMOSPHERE_MAX_TEXTURE_SIZE).
MAX_TEXTURE_SIZE = 4096
## Settings halved for the build.
HALVED = ("scroll_x", "scroll_y", "offset_x", "offset_y")


def load_groups(folder):
    """@return dict group id -> (path, JSON)"""
    groups = {}
    if os.path.isdir(folder):
        for name in sorted(os.listdir(folder)):
            if name.endswith(".json"):
                path = os.path.join(folder, name)
                groups[name[:-5]] = (path, load_json(path))
    return groups


def graphic_exists(graphic):
    base = os.path.join(config.GRAPHICS, graphic)
    return any(os.path.isfile(base + ext) for ext in (".png", ".jpg", ".bmp", ".gif"))


def check_texture_size(graphic, problems, path, where):
    """Warns about graphics too big for many Android GPUs once halved
    (Settings::ATMOSPHERE_MAX_TEXTURE_SIZE, 4096 pixels)."""
    from .importer import png_size
    size = png_size(os.path.join(config.GRAPHICS, graphic + ".png"))
    if size and max(size) // 2 > MAX_TEXTURE_SIZE:
        problems.warning(path, where, "Graphics/%s is %dx%d in the game, larger than %d pixels: the game "
                         "won't draw it (many Android GPUs can't load it)" % (graphic, size[0] // 2,
                                                                               size[1] // 2, MAX_TEXTURE_SIZE))


def compile_layer(raw, problems, path, where, check_graphics=True):
    """Validates a layer and converts it to the runtime form (build scale)."""
    layer = dict(LAYER_DEFAULTS)
    unknown = set(raw) - set(LAYER_DEFAULTS) - {"name"}
    for k in sorted(unknown):
        problems.warning(path, where, "unknown atmosphere setting %r is ignored" % k)
    layer.update({k: v for k, v in raw.items() if k in LAYER_DEFAULTS})
    name = raw.get("name") or ""
    if not name:
        problems.error(path, where, "every atmosphere layer needs a name")
    if not layer["graphic"]:
        problems.error(path, where, "layer %r has no graphic" % name)
    elif check_graphics and os.path.isdir(config.GRAPHICS) and not graphic_exists(layer["graphic"]):
        problems.error(path, where, "graphic Graphics/%s not found in src/assets/graphics" % layer["graphic"])
    elif check_graphics:
        check_texture_size(layer["graphic"], problems, path, where)
    if layer["blend"] not in BLEND_TYPES:
        problems.error(path, where, "blend must be one of %s" % ", ".join(BLEND_TYPES))
        layer["blend"] = "normal"
    z = layer["z"]
    if z not in ("above", "below") and not isinstance(z, (int, float)):
        problems.error(path, where, "z must be \"above\", \"below\" or a number")
        layer["z"] = "above"
    if not isinstance(layer["tone"], list) or len(layer["tone"]) != 4:
        problems.error(path, where, "tone must be [red, green, blue, gray]")
        layer["tone"] = [0, 0, 0, 0]
    if int(layer["frames"]) < 1:
        problems.error(path, where, "frames must be at least 1")
        layer["frames"] = 1
    out = {"name": name}
    for k, v in layer.items():
        if k in HALVED:
            v = v / 2.0
        elif k == "blend":
            v = BLEND_TYPES.index(v)
        out[k] = v
    return out


def compile_groups(groups, problems):
    """@return dict group id -> runtime group"""
    result = {}
    for gid, (path, data) in groups.items():
        names = set()
        layers = []
        for i, raw in enumerate(data.get("layers", [])):
            layer = compile_layer(raw, problems, path, "layers[%d]" % i)
            if layer["name"] in names:
                problems.error(path, "layers[%d]" % i, "two layers are named %r" % layer["name"])
            names.add(layer["name"])
            layers.append(layer)
        result[gid] = {"name": data.get("name", gid), "fade_frames": data.get("fade_frames"), "layers": layers}
    return result


def map_layers(map_data, map_path, problems):
    """The map's own atmosphere layers: image layers inside group layers of
    class (or name) "Atmosphere". Tiled previews them with their parallax and
    repeat settings.

    Image layer -> runtime layer: image (must be under src/assets/graphics),
    opacity, parallaxx/y, repeatx/y, offsetx/y, tintcolor (ignored), plus the
    custom properties z, scroll_x, scroll_y, blend, hue, tone ("r,g,b,gray"),
    zoom_x, zoom_y, frames, frame_duration.
    """
    result = []
    graphics = os.path.normcase(os.path.abspath(config.GRAPHICS)) + os.sep
    for layer, parents in iter_layers(map_data.get("layers", [])):
        if layer.get("type") != "imagelayer":
            continue
        if not any(p.get("class") == CLASS_ATMOSPHERE_GROUP or p.get("name") == CLASS_ATMOSPHERE_GROUP
                   for p in parents):
            continue
        where = "image layer %r" % layer.get("name")
        image = layer.get("image", "")
        full = os.path.normcase(os.path.abspath(os.path.join(os.path.dirname(map_path), image)))
        if not full.startswith(graphics):
            problems.error(map_path, where, "the image must be in src/assets/graphics (any folder)")
            continue
        graphic = os.path.splitext(os.path.relpath(full, graphics.rstrip(os.sep)))[0].replace(os.sep, "/")
        p = props(layer)
        raw = {"name": layer.get("name", ""), "graphic": graphic,
               "opacity": int(round(255 * layer.get("opacity", 1))),
               "parallax_x": layer.get("parallaxx", 1.0), "parallax_y": layer.get("parallaxy", 1.0),
               "repeat_x": bool(layer.get("repeatx", False)), "repeat_y": bool(layer.get("repeaty", False)),
               "offset_x": layer.get("offsetx", 0), "offset_y": layer.get("offsety", 0),
               "visible": layer.get("visible", True)}
        for k in ("z", "scroll_x", "scroll_y", "blend", "hue", "zoom_x", "zoom_y", "frames", "frame_duration"):
            if k in p:
                raw[k] = p[k]
        if "tone" in p:
            try:
                raw["tone"] = [float(x) for x in str(p["tone"]).split(",")]
            except ValueError:
                problems.error(map_path, where, "tone must be 'red, green, blue, gray'")
        check_texture_size(graphic, problems, map_path, where)
        result.append(compile_layer(raw, problems, map_path, where, check_graphics=False))
    return result


def legacy_group(tileset):
    """An atmosphere group from an RMXP tileset's panorama and fog (importer).

    @param tileset the exported Tilesets.rxdata entry
    @return group JSON, or None if the tileset has neither
    """
    layers = []
    if tileset.get("panorama_name"):
        layers.append({"name": "panorama", "graphic": "Panoramas/" + tileset["panorama_name"], "z": "below",
                       "parallax_x": 0.5, "parallax_y": 0.5, "hue": tileset.get("panorama_hue", 0)})
    if tileset.get("fog_name"):
        # RMXP: fog_ox -= fog_sx * 5 pixels per second at the build's scale,
        # which is 10 pixels per second at the 32px source scale.
        layers.append({"name": "fog", "graphic": "Fogs/" + tileset["fog_name"], "z": "above",
                       "hue": tileset.get("fog_hue", 0), "opacity": tileset.get("fog_opacity", 64),
                       "blend": BLEND_TYPES[tileset.get("fog_blend_type", 0)] if tileset.get("fog_blend_type", 0) < 3 else "normal",
                       "zoom_x": tileset.get("fog_zoom", 100), "zoom_y": tileset.get("fog_zoom", 100),
                       "scroll_x": tileset.get("fog_sx", 0) * 10, "scroll_y": tileset.get("fog_sy", 0) * 10})
    if not layers:
        return None
    return {"name": tileset.get("name", ""), "layers": layers}


def world_positions(placed):
    """Map id -> [x, y] in tiles, for scrolling by world position."""
    return {p.map_id: [p.x, p.y] for p in placed}


def runtime_data(groups, maps, world):
    """The atmospheres.dat content.

    @param maps dict map id -> {"group": id or None, "layers": [...]}
    """
    return {"groups": groups, "maps": {str(k): v for k, v in maps.items()},
            "world": {str(k): v for k, v in world.items()}}


