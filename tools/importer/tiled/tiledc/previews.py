"""@package tiledc.previews
Images Tiled shows for event graphics.

For every character sheet in Graphics/Characters (4 directions x 4 frames),
the first frame of each direction is saved in src/tiled/generated/characters
and listed in the image collection tileset generated/characters.tsj (class
CharacterPreview). The Tiled extension shows an event with the tile matching
its first page's graphic and direction. The compiler ignores this tileset, and
the folder is gitignored: run `make tiled-assets` to recreate it.
"""

import os

from . import config
from .tiledio import TILED_EDITOR_VERSION, TILED_VERSION, make_prop, relpath, save_json

## Direction rows of a character sheet.
ROWS = ["down", "left", "right", "up"]


def write_previews(paths):
    """@return number of preview images"""
    from PIL import Image
    src = os.path.join(config.GRAPHICS, "Characters")
    out = os.path.join(paths.generated, "characters")
    os.makedirs(out, exist_ok=True)
    tsj = os.path.join(paths.generated, "characters.tsj")
    tiles = []
    max_w = max_h = config.TILE
    for root, _, files in os.walk(src):
        for name in sorted(files):
            if not name.lower().endswith(".png"):
                continue
            graphic = os.path.splitext(os.path.relpath(os.path.join(root, name), src))[0].replace(os.sep, "/")
            with Image.open(os.path.join(root, name)) as im:
                im = im.convert("RGBA")
                fw, fh = max(1, im.width // 4), max(1, im.height // 4)
                for row, direction in enumerate(ROWS):
                    frame = im.crop((0, row * fh, fw, (row + 1) * fh))
                    file = os.path.join(out, "%s__%s.png" % (graphic.replace("/", "__"), direction))
                    frame.save(file)
                    max_w, max_h = max(max_w, fw), max(max_h, fh)
                    tile = {"id": len(tiles), "image": relpath(file, tsj), "imageheight": fh, "imagewidth": fw,
                            "properties": [make_prop("direction", direction), make_prop("graphic", graphic)]}
                    tiles.append(tile)
    save_json(tsj, {"class": config.CLASS_PREVIEW, "columns": 0, "grid": {"height": 1, "orientation": "orthogonal",
                                                                       "width": 1},
                    "margin": 0, "name": "Event previews", "spacing": 0, "tilecount": len(tiles),
                    "tiledversion": TILED_EDITOR_VERSION, "tileheight": max_h, "tiles": tiles,
                    "tilewidth": max_w, "type": "tileset", "version": TILED_VERSION})
    return len(tiles)
