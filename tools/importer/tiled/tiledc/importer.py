"""@package tiledc.importer
Imports RPG Maker XP data (src/assets/data/*.rxdata, as installed by
`make install-assets`) and the map datasets of src/pbs into src/tiled:

  * MapInfos      -> maps/registry.json
  * Map###        -> maps/###_<name>.tmj (3 tile layers, an "Events" object
                     layer and an empty "Atmosphere" group), events/<map>/*.rb
  * Tilesets      -> tilesets/*.tsj with TileData on every tile that has
                     passage, priority or terrain data; autotiles converted
                     into tilesets/autotiles; registry.json keeps the ids
  * fog/panorama  -> atmospheres/tileset_<name>.json
  * CommonEvents  -> common_events/*.rb
  * System        -> system.json
  * map_metadata, encounters -> map properties
  * map_connections -> maps/pokessentials.world (and explicit "connections"
                     properties for the few that don't fit in one world)

After importing, the map datasets are removed from src/pbs (the maps own
them now; they're still in git history).
"""

import json
import os
import struct
import subprocess
import tempfile

from . import atmosphere, autotiles, config, connections, events, pbsmaps
from .config import AUTOTILE_TILES, TILE, TILESET_COLUMNS, TILESET_START_ID
from .problems import TiledError
from .registry import Registry, slug
from .tiledio import (TILED_EDITOR_VERSION, TILED_VERSION, make_prop, relpath, save_json, set_props,
                      tile_layer, write_if_changed)
from .tiles import TerrainTags, TILE_DATA, TilesetRegistry, tile_data_prop, to_tile_data


def png_size(path):
    """(width, height) of a PNG, read from its header, or None."""
    try:
        with open(path, "rb") as f:
            head = f.read(24)
        if head[:8] == b"\x89PNG\r\n\x1a\n":
            return struct.unpack(">II", head[16:24])
    except OSError:
        pass
    return None


def export_rxdata(data_dir, ruby="ruby", only_tilesets=False):
    """Runs rxdata_export.rb. @return the exported JSON"""
    if not os.path.isfile(os.path.join(data_dir, "Tilesets.rxdata")):
        raise TiledError("%s has no Tilesets.rxdata (run `make install-assets` first, or pass the "
                         "folder of an Essentials project's Data)" % data_dir)
    fd, tmp = tempfile.mkstemp(prefix="rxdata_", suffix=".json")
    os.close(fd)
    try:
        cmd = [ruby, os.path.join(config.RUBY_DIR, "rxdata_export.rb"), data_dir, tmp]
        if only_tilesets:
            cmd.append("--only-tilesets")
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if proc.returncode != 0:
            raise TiledError("rxdata_export.rb failed:\n" + proc.stderr.decode("utf-8", "replace"))
        with open(tmp, encoding="utf-8") as f:
            return json.load(f)
    finally:
        os.remove(tmp)


class TilesetWriter:
    """Writes deduplicated .tsj files for RMXP tilesets and autotiles."""

    def __init__(self, paths, log, warn):
        self.paths = paths
        self.log = log
        self.warn = warn
        self.tags = TerrainTags()
        self.regular = {}     # (image, data) -> tsj path
        self.autos = {}       # (name, data) -> tsj path
        self.used_names = set()

    def _unique(self, folder, stem):
        name, n = stem, 2
        while os.path.join(folder, name) in self.used_names:
            name = "%s_%d" % (stem, n)
            n += 1
        self.used_names.add(os.path.join(folder, name))
        return os.path.join(folder, name + ".tsj")

    def regular_tileset(self, ts):
        """@return (tsj path, tile count) of an RMXP tileset's regular tiles"""
        name = ts["tileset_name"]
        size = len(ts["passages"])
        datas = []
        for i in range(TILESET_START_ID, size):
            datas.append(to_tile_data(ts["passages"][i], ts["priorities"][i], ts["terrain_tags"][i], self.tags))
        image = os.path.join(config.GRAPHICS, "Tilesets", name + ".png")
        dims = png_size(image)
        if dims:
            columns = dims[0] // TILE
            count = columns * (dims[1] // TILE)
        else:
            self.warn("tileset image Graphics/Tilesets/%s.png not found; its size is guessed from the "
                      "tileset data" % name)
            columns, count = TILESET_COLUMNS, size - TILESET_START_ID
            dims = (columns * TILE, ((count + columns - 1) // columns) * TILE)
        datas = datas[:count]
        key = (name, json.dumps(datas, sort_keys=True))
        if key in self.regular:
            return self.regular[key], count
        path = self._unique(self.paths.tilesets, slug(name))
        tiles = [{"id": i, "properties": [tile_data_prop(d)]} for i, d in enumerate(datas) if d]
        doc = {"columns": columns, "image": relpath(image, path), "imageheight": dims[1],
               "imagewidth": dims[0], "margin": 0, "name": name, "spacing": 0, "tilecount": count,
               "tiledversion": TILED_EDITOR_VERSION, "tileheight": TILE, "tilewidth": TILE,
               "type": "tileset", "version": TILED_VERSION}
        if tiles:
            doc["tiles"] = tiles
        save_json(path, doc)
        self.regular[key] = path
        return path, count

    def autotile(self, ts, slot):
        """@return tsj path of autotile `slot` (0-6) of an RMXP tileset"""
        name = ts["autotile_names"][slot]
        base = AUTOTILE_TILES * (slot + 1)
        datas = [to_tile_data(ts["passages"][base + k], ts["priorities"][base + k], ts["terrain_tags"][base + k],
                              self.tags) for k in range(AUTOTILE_TILES)]
        key = (name, json.dumps(datas, sort_keys=True))
        if key in self.autos:
            return self.autos[key]
        os.makedirs(self.paths.autotiles, exist_ok=True)
        path = self._unique(self.paths.autotiles, slug(name))
        stem = os.path.splitext(os.path.basename(path))[0]
        src = os.path.join(config.GRAPHICS, "Autotiles", name + ".png")
        if os.path.isfile(src):
            try:
                autotiles.convert(src, self.paths.autotiles, name, stem)
            except ImportError:
                self.warn("Pillow isn't installed: autotile %s wasn't converted (run `make tiled-assets` "
                          "after installing it)" % name)
                self._placeholder_autotile(path, name)
        else:
            self.warn("autotile Graphics/Autotiles/%s.png not found; run `make tiled-assets` once it's "
                      "installed" % name)
            self._placeholder_autotile(path, name)
        from .tiledio import load_json
        doc = load_json(path)
        same = all(d == datas[0] for d in datas)
        props_list = [p for p in doc.get("properties", []) if p["name"] != TILE_DATA]
        doc["properties"] = props_list
        set_props(doc, [tile_data_prop(datas[0] if same else {})])
        if not same:
            tiles = {t["id"]: t for t in doc.get("tiles", [])}
            for k, d in enumerate(datas):
                if d:
                    t = tiles.setdefault(k, {"id": k})
                    set_props(t, [tile_data_prop(d)])
            doc["tiles"] = [tiles[k] for k in sorted(tiles)]
        save_json(path, doc)
        self.autos[key] = path
        return path

    def _placeholder_autotile(self, path, name):
        png = os.path.splitext(path)[0] + ".png"
        save_json(path, autotiles.tileset_json(name, png, path, 1, False, name))


def import_rxdata(paths, data_dir, pbs_src=config.PBS_SRC, ruby="ruby", force=False, keep_pbs=False,
                  log=print, warn=None):
    """Imports RMXP data into a Tiled source folder.

    @return number of maps imported
    """
    warnings = []
    warn = warn or (lambda m: warnings.append(m) or print("warning: " + m))
    if paths.exists() and not force:
        raise TiledError("%s already exists; importing would overwrite your Tiled maps (use --force)."
                         % paths.rel(paths.registry))
    data = export_rxdata(data_dir, ruby)
    for folder in (paths.maps, paths.tilesets, paths.events, paths.common_events, paths.atmospheres):
        os.makedirs(folder, exist_ok=True)

    # Tilesets
    writer = TilesetWriter(paths, log, warn)
    ts_registry = TilesetRegistry(paths.tileset_registry)
    ts_registry.entries = []
    by_id = {}
    for ts in data["tilesets"]:
        if not ts["tileset_name"] and not any(ts["autotile_names"]):
            continue
        regular = []
        count = 0
        if ts["tileset_name"]:
            path, count = writer.regular_tileset(ts)
            regular.append(path)
        slots = {}
        for slot, name in enumerate(ts["autotile_names"]):
            if name:
                slots[slot] = writer.autotile(ts, slot)
        group = atmosphere.legacy_group(ts)
        group_id = None
        if group:
            group_id = "tileset_" + slug(ts["name"] or ts["tileset_name"])
            save_json(os.path.join(paths.atmospheres, group_id + ".json"), group)
        rel = lambda p: os.path.relpath(p, paths.tilesets).replace(os.sep, "/")
        key = ([rel(p) for p in regular], [rel(slots[s]) for s in sorted(slots)])
        if not ts_registry.find(*key):
            ts_registry.entries.append({"id": ts["id"], "name": ts["name"], "tilesets": key[0], "autotiles": key[1]})
        by_id[ts["id"]] = {"regular": regular, "count": count, "slots": slots, "atmosphere": group_id,
                           "names": {}}
    ts_registry.save()

    # Map datasets from src/pbs
    metadata, encounters, conns = pbsmaps.read_pbs_maps(pbs_src) if os.path.isdir(pbs_src) else ([], [], [])
    meta_by_map = {m["id"]: m for m in metadata}
    enc_by_map = {}
    for e in encounters:
        enc_by_map.setdefault(e["map"], []).append(e)
    fields = pbsmaps.metadata_fields()

    # Registry
    registry = Registry(paths.registry, [])
    infos = data["mapinfos"]
    for sid in sorted(infos, key=int):
        info = infos[sid]
        mid = int(sid)
        if sid not in data["maps"]:
            warn("map %d (%s) is in MapInfos but has no Map%03d.rxdata; skipped" % (mid, info["name"], mid))
            continue
        e = registry.add(info["name"], map_id=mid, parent=info["parent_id"])
        e["order"] = info["order"]
        e["expanded"] = info["expanded"]
        e["scroll_x"], e["scroll_y"] = info["scroll_x"], info["scroll_y"]

    # World
    sizes = {int(k): (m["width"], m["height"]) for k, m in data["maps"].items() if registry.by_id(int(k))}
    placed, leftover = connections.layout(sizes, conns)
    explicit = {}
    for c in leftover:
        explicit.setdefault(c[0], []).append(c)
    registry.save()
    connections.save_world(paths.world, registry, placed.values())

    # Maps
    for e in registry.entries:
        mid = e["id"]
        m = data["maps"][str(mid)]
        path = registry.map_path(e)
        tinfo = by_id.get(m["tileset_id"])
        if tinfo is None:
            warn("map %d uses tileset %d, which doesn't exist; its tiles are dropped" % (mid, m["tileset_id"]))
            tinfo = {"regular": [], "count": 0, "slots": {}, "atmosphere": None}
        tilesets, firstgid, auto_gid = [], 1, {}
        regular_gid = None
        for p in tinfo["regular"]:
            tilesets.append({"firstgid": firstgid, "source": relpath(p, path)})
            regular_gid = firstgid
            firstgid += tinfo["count"]
        for slot in sorted(tinfo["slots"]):
            tilesets.append({"firstgid": firstgid, "source": relpath(tinfo["slots"][slot], path)})
            auto_gid[slot] = firstgid
            from .tiledio import load_json
            firstgid += load_json(tinfo["slots"][slot]).get("tilecount", AUTOTILE_TILES)
        names = {}
        for p in tinfo["regular"]:
            names["regular"] = os.path.splitext(os.path.basename(p))[0]
        for slot, p in tinfo["slots"].items():
            names[slot] = os.path.splitext(os.path.basename(p))[0]

        def gid_of(tid, counter):
            if tid == 0:
                return 0
            if tid < AUTOTILE_TILES:
                counter[0] += 1
                return 0
            if tid < TILESET_START_ID:
                slot = tid // AUTOTILE_TILES - 1
                if slot not in auto_gid:
                    counter[0] += 1
                    return 0
                return auto_gid[slot] + tid % AUTOTILE_TILES
            local = tid - TILESET_START_ID
            if regular_gid is None or local >= tinfo["count"]:
                counter[0] += 1
                return 0
            return regular_gid + local

        def tile_name(tid):
            if tid >= TILESET_START_ID and "regular" in names:
                return "%s:%d" % (names["regular"], tid - TILESET_START_ID)
            slot = tid // AUTOTILE_TILES - 1
            if slot in names:
                return "%s:%d" % (names[slot], tid % AUTOTILE_TILES)
            return ""

        w, h = m["width"], m["height"]
        invalid = [0]
        layers = []
        layer_id = 1
        for z in range(3):
            chunk = m["data"][z * w * h:(z + 1) * w * h]
            layers.append(tile_layer("Layer %d" % (z + 1), w, h, [gid_of(t, invalid) for t in chunk], layer_id))
            layer_id += 1
        if invalid[0]:
            warn("map %d (%s): %d invalid tiles were dropped" % (mid, e["name"], invalid[0]))
        # Events
        folder = events.events_folder(paths, path)
        objects = []
        object_id = 1
        for ev in m["events"]:
            script_rel = None
            lines = ev["source"].splitlines()
            if any(line.startswith("page ") and not line.rstrip().endswith("[]") for line in lines) or \
                    any(line.startswith("move_route ") for line in lines):
                os.makedirs(folder, exist_ok=True)
                script = os.path.join(folder, events.script_file_name(ev["id"], ev["name"]))
                write_if_changed(script, ev["source"])
                script_rel = relpath(script, path)
            pages = [events.settings_to_page(s, tile_name) for s in ev["pages"]]
            objects.append(events.new_event_object(object_id, ev["id"], ev["name"], ev["x"], ev["y"], pages,
                                                   script_rel))
            object_id += 1
        layers.append({"draworder": "topdown", "id": layer_id, "name": "Events", "objects": objects,
                       "opacity": 1, "type": "objectgroup", "visible": True, "x": 0, "y": 0})
        layer_id += 1
        layers.append({"id": layer_id, "layers": [], "name": "Atmosphere", "class": config.CLASS_ATMOSPHERE_GROUP,
                       "opacity": 1, "type": "group", "visible": True, "x": 0, "y": 0})
        layer_id += 1
        doc = {"class": "Map", "compressionlevel": -1, "height": h, "infinite": False, "layers": layers,
               "nextlayerid": layer_id, "nextobjectid": object_id, "orientation": "orthogonal",
               "renderorder": "right-down", "tiledversion": TILED_EDITOR_VERSION, "tileheight": TILE,
               "tilesets": tilesets, "tilewidth": TILE, "type": "map", "version": TILED_VERSION, "width": w}
        entries = []
        if m["bgm"]["name"] or m["autoplay_bgm"]:
            entries.append(make_prop("bgm", m["bgm"], "class", "Audio"))
            entries.append(make_prop("autoplay_bgm", bool(m["autoplay_bgm"]), "bool"))
        if m["bgs"]["name"] or m["autoplay_bgs"]:
            entries.append(make_prop("bgs", m["bgs"], "class", "Audio"))
            entries.append(make_prop("autoplay_bgs", bool(m["autoplay_bgs"]), "bool"))
        if m["encounter_step"] != 30:
            entries.append(make_prop("encounter_step", m["encounter_step"], "int"))
        if mid in meta_by_map:
            entries.append(make_prop("metadata", pbsmaps.metadata_to_props(meta_by_map[mid], fields),
                                     "class", "MapMetadata"))
        for enc in enc_by_map.get(mid, []):
            name, value = pbsmaps.encounters_to_props(enc)
            entries.append(make_prop(name, value, "class", "Encounters"))
        if tinfo.get("atmosphere"):
            entries.append(make_prop("atmosphere", tinfo["atmosphere"], "string"))
        if mid in explicit:
            lines = []
            for c in explicit[mid]:
                other = registry.by_id(c[3])
                lines.append("%s %d %s %s %d" % (c[1], c[2], other["name"] if other and
                                                  registry.name_to_id().get(other["name"]) == c[3] else c[3],
                                                  c[4], c[5]))
            entries.append(make_prop("connections", "; ".join(lines), "string"))
        if entries:
            set_props(doc, entries)
        save_json(path, doc)

    # Common events and system
    for ce in data["common_events"]:
        name = "%03d_%s.rb" % (ce["id"], slug(ce["name"]) if ce["name"] else "common_event")
        write_if_changed(os.path.join(paths.common_events, name), ce["source"])
    if data.get("system"):
        save_json(paths.system, data["system"])

    if not keep_pbs and os.path.isdir(pbs_src):
        for removed in pbsmaps.remove_pbs_maps(pbs_src):
            log("Removed %s (now stored on the Tiled maps)." % config.Paths().rel(removed))
    log("Imported %d maps, %d tilesets, %d autotiles and %d common events into %s."
        % (len(registry.entries), len(writer.regular), len(writer.autos), len(data["common_events"]),
           paths.rel(paths.src)))
    return len(registry.entries)


def import_tile_data(paths, tsj_path, source, ruby="ruby", rmxp_id=None, log=print):
    """Copies tile data into an existing .tsj, matching tiles by position.

    @param source a Tilesets.rxdata (with rmxp_id) or a JSON/CSV dump made by
        export_tile_data
    @return number of tiles changed
    """
    from .tiledio import load_json, props, tiles_by_id
    tags = TerrainTags()
    doc = load_json(tsj_path)
    if source.endswith(".rxdata"):
        data = export_rxdata(os.path.dirname(os.path.abspath(source)), ruby, only_tilesets=True)
        match = [t for t in data["tilesets"] if rmxp_id is None or t["id"] == rmxp_id]
        if not match:
            raise TiledError("no tileset %s in %s" % (rmxp_id, source))
        ts = match[0]
        is_auto = doc.get("class") == config.CLASS_AUTOTILE
        base = TILESET_START_ID
        if is_auto:
            names = ts["autotile_names"]
            want = props(doc).get("autotile")
            if want not in names:
                raise TiledError("tileset %d has no autotile %r" % (ts["id"], want))
            base = AUTOTILE_TILES * (names.index(want) + 1)
        count = AUTOTILE_TILES if is_auto else doc.get("tilecount", 0)
        datas = {}
        for i in range(count):
            if base + i < len(ts["passages"]):
                datas[i] = to_tile_data(ts["passages"][base + i], ts["priorities"][base + i],
                                        ts["terrain_tags"][base + i], tags)
    else:
        datas = {int(k): v for k, v in read_tile_dump(source).items()}
    tiles = tiles_by_id(doc)
    changed = 0
    for i, d in datas.items():
        if i >= doc.get("tilecount", 0):
            continue
        t = tiles.get(i)
        old = props(t).get(TILE_DATA) if t else None
        if (old or {}) == (d or {}):
            continue
        t = tiles.setdefault(i, {"id": i})
        if d:
            set_props(t, [tile_data_prop(d)])
        else:
            from .tiledio import remove_props
            remove_props(t, [TILE_DATA])
        changed += 1
    doc["tiles"] = [tiles[k] for k in sorted(tiles) if len(tiles[k]) > 1]
    if not doc["tiles"]:
        del doc["tiles"]
    save_json(tsj_path, doc)
    log("Updated the tile data of %d tiles in %s." % (changed, paths.rel(tsj_path)))
    return changed


#===============================================================================
# Tile data dumps
#===============================================================================
## CSV columns of a tile data dump.
DUMP_COLUMNS = ["tile", "block_down", "block_left", "block_right", "block_up", "bush", "counter",
                "priority", "terrain_tag", "extra_passage"]


def export_tile_data(tsj_path, out_path):
    """Writes the TileData of every tile of a .tsj as JSON or CSV (by extension)."""
    from .tiles import TilesetInfo, DEFAULT_TILE_DATA
    info = TilesetInfo(tsj_path)
    count = info.tilecount if info.kind != "autotile" else AUTOTILE_TILES
    rows = {}
    for i in range(count):
        d = dict(DEFAULT_TILE_DATA)
        d.update(info.tile_data(i))
        rows[i] = d
    if out_path.endswith(".csv"):
        import csv
        import io
        buf = io.StringIO()
        w = csv.writer(buf, lineterminator="\n")
        w.writerow(DUMP_COLUMNS)
        for i, d in rows.items():
            w.writerow([i] + [int(d[c]) if isinstance(d[c], bool) else d[c] for c in DUMP_COLUMNS[1:]])
        write_if_changed(out_path, buf.getvalue())
    else:
        save_json(out_path, {"tileset": info.name, "tiles": {str(k): v for k, v in rows.items()}})


def read_tile_dump(path):
    """Reads a dump from export_tile_data. @return dict tile -> TileData (non-defaults)"""
    from .tiles import DEFAULT_TILE_DATA
    result = {}
    if path.endswith(".csv"):
        import csv
        with open(path, encoding="utf-8") as f:
            for row in csv.DictReader(f):
                d = {}
                for c in DUMP_COLUMNS[1:]:
                    v = row.get(c, "")
                    if c in ("priority", "extra_passage"):
                        v = int(v or 0)
                    elif c != "terrain_tag":
                        v = v.strip().lower() in ("1", "true", "yes")
                    d[c] = v
                result[int(row["tile"])] = d
    else:
        from .tiledio import load_json
        for k, v in load_json(path).get("tiles", {}).items():
            result[int(k)] = v
    return {k: {m: v for m, v in d.items() if v != DEFAULT_TILE_DATA.get(m)} for k, d in result.items()}
