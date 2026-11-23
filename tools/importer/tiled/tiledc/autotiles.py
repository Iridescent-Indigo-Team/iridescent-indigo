"""@package tiledc.autotiles
Converts RPG Maker XP autotiles into Tiled tilesets.

An RMXP autotile is a 48x64 sheet (3x4 16px tiles) per animation frame,
frames side by side; the engine assembles each of its 48 variants from 8x8
quarters (TileDrawingHelper::AUTOTILE_PATTERNS). A "small" autotile is a
single 16x16 tile per frame, used for all 48 variants.

The converter writes, for each autotile, a PNG with the 48 variants of every
frame (8 columns x 6 rows per frame, frames stacked) and a .tsj that:
  * has class "Autotile" and an "autotile" property (the RMXP graphic name),
  * animates tile k through k + 48*f when there are several frames,
  * has a Tiled terrain (Wang) set, so the variants paint with the terrain
    brush the way RMXP's autotile pen does.
Local tile k is RMXP variant k, so the compiler maps it to 48*(slot+1) + k.
"""

import os
import re

from . import config
from .tiledio import (TILED_EDITOR_VERSION, TILED_VERSION, load_json, make_prop, props, relpath,
                      save_json, set_props)
from .tiles import TILE_DATA

## The 48 variants: quarter numbers (1-based, in a 6x8 grid of 16px quarters)
## for the top-left, top-right, bottom-left and bottom-right quarters.
## Same table as TileDrawingHelper::AUTOTILE_PATTERNS, flattened.
PATTERNS = [
    [27, 28, 33, 34], [5, 28, 33, 34], [27, 6, 33, 34], [5, 6, 33, 34],
    [27, 28, 33, 12], [5, 28, 33, 12], [27, 6, 33, 12], [5, 6, 33, 12],
    [27, 28, 11, 34], [5, 28, 11, 34], [27, 6, 11, 34], [5, 6, 11, 34],
    [27, 28, 11, 12], [5, 28, 11, 12], [27, 6, 11, 12], [5, 6, 11, 12],
    [25, 26, 31, 32], [25, 6, 31, 32], [25, 26, 31, 12], [25, 6, 31, 12],
    [15, 16, 21, 22], [15, 16, 21, 12], [15, 16, 11, 22], [15, 16, 11, 12],
    [29, 30, 35, 36], [29, 30, 11, 36], [5, 30, 35, 36], [5, 30, 11, 36],
    [39, 40, 45, 46], [5, 40, 45, 46], [39, 6, 45, 46], [5, 6, 45, 46],
    [25, 30, 31, 36], [15, 16, 45, 46], [13, 14, 19, 20], [13, 14, 19, 12],
    [17, 18, 23, 24], [17, 18, 11, 24], [41, 42, 47, 48], [5, 42, 47, 48],
    [37, 38, 43, 44], [37, 6, 43, 44], [13, 18, 19, 24], [13, 14, 43, 44],
    [37, 42, 43, 48], [17, 18, 47, 48], [13, 18, 43, 48], [1, 2, 7, 8],
]
## Quarter size of a tile.
QUARTER = config.TILE // 2
## Width and height of one full autotile frame.
FRAME_W, FRAME_H = 3 * config.TILE, 4 * config.TILE


def _quarter_edges(number, corner):
    """Which neighbours a quarter assumes are the same terrain.

    @param number quarter number (1-based)
    @param corner 0 top-left, 1 top-right, 2 bottom-left, 3 bottom-right
    @return (vertical edge present, horizontal edge present, corner present)
        where "vertical edge" is top for top quarters / bottom for bottom ones
    """
    qx, qy = (number - 1) % 6, (number - 1) // 6
    if qy < 2:
        if qx >= 4:          # inner-corner tile: both edges, no corner
            return True, True, False
        return False, False, False    # isolated tile
    col, row = qx // 2, (qy - 2) // 2
    top = corner in (0, 1)
    left = corner in (0, 2)
    vertical = row > 0 if top else row < 2
    horizontal = col > 0 if left else col < 2
    return vertical, horizontal, vertical and horizontal


def wang_id(variant):
    """Tiled "mixed" Wang id of a variant: colours of the top, top-right,
    right, bottom-right, bottom, bottom-left, left and top-left neighbours
    (1 = same terrain, 0 = none)."""
    q = PATTERNS[variant]
    tl, tr, bl, br = (_quarter_edges(q[i], i) for i in range(4))
    top = tl[0] and tr[0]
    bottom = bl[0] and br[0]
    left = tl[1] and bl[1]
    right = tr[1] and br[1]
    return [int(top), int(tr[2] and top and right), int(right), int(br[2] and bottom and right),
            int(bottom), int(bl[2] and bottom and left), int(left), int(tl[2] and top and left)]


def frame_duration(name):
    """RMXP frame duration of an autotile, in 1/20ths of a second (a "[n]"
    suffix on the file name overrides the default)."""
    m = re.search(r"\[\s*(\d+?)\s*\]\s*$", name)
    return int(m.group(1)) if m else config.AUTOTILE_FRAME_DURATION


def expand(image):
    """The 48 variants of every frame of an autotile.

    @param image PIL image of the RMXP autotile
    @return (PIL image 8x6 tiles per frame, frames stacked; frame count)
    """
    from PIL import Image
    image = image.convert("RGBA")
    t = config.TILE
    small = image.height < FRAME_H
    frame_w = t if small else FRAME_W
    frames = max(1, image.width // frame_w)
    out = Image.new("RGBA", (8 * t, 6 * t * frames), (0, 0, 0, 0))
    for f in range(frames):
        ox = f * frame_w
        for k in range(48):
            dx, dy = (k % 8) * t, (f * 6 + k // 8) * t
            if small:
                out.paste(image.crop((ox, 0, ox + t, t)), (dx, dy))
                continue
            for i, number in enumerate(PATTERNS[k]):
                qx, qy = (number - 1) % 6, (number - 1) // 6
                src = image.crop((ox + qx * QUARTER, qy * QUARTER, ox + (qx + 1) * QUARTER, (qy + 1) * QUARTER))
                out.paste(src, (dx + (i % 2) * QUARTER, dy + (i // 2) * QUARTER))
    return out, frames


def tileset_json(name, image_file, tsj_path, frames, small, autotile_name, old=None):
    """The .tsj of a converted autotile, keeping the properties and tile data
    of an older version (old)."""
    t = config.TILE
    duration_ms = frame_duration(autotile_name) * 50
    tiles = {}
    if old:
        for tile in old.get("tiles", []) or []:
            keep = {k: v for k, v in tile.items() if k not in ("animation",)}
            if len(keep) > 1:
                tiles[tile["id"]] = keep
    if frames > 1:
        for k in range(48):
            entry = tiles.setdefault(k, {"id": k})
            entry["animation"] = [{"tileid": k + 48 * f, "duration": duration_ms} for f in range(frames)]
    data = {
        "class": config.CLASS_AUTOTILE,
        "columns": 8,
        "image": relpath(image_file, tsj_path),
        "imageheight": 6 * t * frames,
        "imagewidth": 8 * t,
        "margin": 0,
        "name": name,
        "spacing": 0,
        "tilecount": 48 * frames,
        "tiledversion": TILED_EDITOR_VERSION,
        "tileheight": t,
        "tilewidth": t,
        "type": "tileset",
        "version": TILED_VERSION,
    }
    if tiles:
        data["tiles"] = [tiles[k] for k in sorted(tiles)]
    if not small:
        data["wangsets"] = [{
            "colors": [{"color": "#2f8fd8", "name": name, "probability": 1, "tile": 0}],
            "name": name, "tile": 0, "type": "mixed",
            "wangtiles": [{"tileid": k, "wangid": wang_id(k)} for k in range(48)],
        }]
    data["properties"] = (old or {}).get("properties", [])
    set_props(data, [make_prop("autotile", autotile_name, "string")])
    if TILE_DATA not in props(data):
        set_props(data, [make_prop(TILE_DATA, {}, "class", TILE_DATA)])
    return data


def convert(src_png, out_dir, autotile_name=None, slug_name=None):
    """Converts one RMXP autotile into <out_dir>/<slug>.png and .tsj.

    @param src_png the RMXP autotile (Graphics/Autotiles/<name>.png, 16px tiles)
    @param autotile_name RMXP graphic name (default: file name without .png)
    @return path of the .tsj
    """
    from PIL import Image
    from .registry import slug
    autotile_name = autotile_name or os.path.splitext(os.path.basename(src_png))[0]
    stem = slug_name or slug(autotile_name)
    png = os.path.join(out_dir, stem + ".png")
    tsj = os.path.join(out_dir, stem + ".tsj")
    with Image.open(src_png) as im:
        small = im.height < FRAME_H
        expanded, frames = expand(im)
    os.makedirs(out_dir, exist_ok=True)
    expanded.save(png)
    old = load_json(tsj) if os.path.isfile(tsj) else None
    save_json(tsj, tileset_json(autotile_name, png, tsj, frames, small, autotile_name, old))
    return tsj
