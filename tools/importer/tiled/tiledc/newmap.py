"""@package tiledc.newmap
Creating maps from the command line (the Tiled extension does the same from
inside Tiled).
"""

import os

from . import config, connections
from .problems import TiledError
from .tiledio import TILED_EDITOR_VERSION, TILED_VERSION, load_json, relpath, save_json, tile_layer


def empty_map(width, height, tileset_refs):
    """A new map document.

    @param tileset_refs list of {"firstgid", "source"} (sources relative to the map)
    """
    layers = [tile_layer("Layer %d" % (i + 1), width, height, [0] * (width * height), i + 1) for i in range(3)]
    layers.append({"draworder": "topdown", "id": 4, "name": "Events", "objects": [], "opacity": 1,
                   "type": "objectgroup", "visible": True, "x": 0, "y": 0})
    layers.append({"class": config.CLASS_ATMOSPHERE_GROUP, "id": 5, "layers": [], "name": "Atmosphere",
                   "opacity": 1, "type": "group", "visible": True, "x": 0, "y": 0})
    return {"class": "Map", "compressionlevel": -1, "height": height, "infinite": False, "layers": layers,
            "nextlayerid": 6, "nextobjectid": 1, "orientation": "orthogonal", "renderorder": "right-down",
            "tiledversion": TILED_EDITOR_VERSION, "tileheight": config.TILE, "tilesets": tileset_refs,
            "tilewidth": config.TILE, "type": "map", "version": TILED_VERSION, "width": width}


def new_map(paths, registry, name, width, height, tilesets=(), parent=0):
    """Registers a map, writes its .tmj and adds it to the world (apart from
    the other maps, so it isn't connected until you move it).

    @return path of the new .tmj
    """
    if width < 1 or height < 1:
        raise TiledError("maps need a width and height of at least 1")
    entry = registry.add(name, parent=parent)
    path = registry.map_path(entry)
    refs, firstgid = [], 1
    for ts in tilesets:
        full = os.path.abspath(ts)
        if not os.path.isfile(full):
            raise TiledError("%s doesn't exist" % ts)
        refs.append({"firstgid": firstgid, "source": relpath(full, path)})
        firstgid += load_json(full).get("tilecount", 0)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    save_json(path, empty_map(width, height, refs))
    registry.save()
    placed, _ = connections.load_world(paths.world, registry)
    right = max([p.x + p.width for p in placed] + [0])
    placed.append(connections.Placed(entry["id"], right + 8 if placed else 0, 0, width, height))
    connections.save_world(paths.world, registry, placed)
    return path
