"""@package tiledc.compiler
Validates src/tiled and compiles it into the game's data.

Per map:
  1. Rules: orthogonal, not infinite, 32px tiles, tilesets saved as .tsj with
     32px tiles, no flipped or rotated tiles, at most 7 autotiles, at most 3
     tiles per cell, every tile layer the size of the map.
  2. Tile numbering across tilesets: a gid's tileset is found by firstgid;
     autotile k becomes RMXP ids 48*(k+1)+local, regular tilesets are stacked
     into one combined RMXP tileset (384 + 8*row + column), shared by every map
     that uses the same tilesets (ids in src/tiled/tilesets/registry.json).
  3. Tile layers are flattened bottom to top into RMXP's 3 layers.
  4. Events, spawns, metadata, encounters, connections and atmospheres are
     collected.
  5. Sideways stairs rules are checked (see stairs.py).
Then the Ruby back end (ruby/rxdata_build.rb) evaluates the event scripts and
writes the .rxdata files, and the PBS JSON overlay is written for `make pbs`.
"""

import hashlib
import json
import os
import subprocess
import tempfile

from . import atmosphere, config, connections, events, pbsmaps, stairs
from .config import AUTOTILE_SLOTS, AUTOTILE_TILES, RMXP_LAYERS, TILE
from .problems import Problems, TiledError
from .registry import Registry
from .tiledio import (iter_layers, layer_gids, load_json, map_tilesets, props, prop_types, split_gid,
                      tileset_for_gid, write_if_changed)
from .tiles import Combined, TerrainTags, TilesetInfo, TilesetRegistry

## Most problems reported per layer for repeated tile errors.
MAX_TILE_PROBLEMS = 5
## Files in build/Data the compiler writes (halve_data.rb skips them).
OWNED_PATTERNS = [r"Map\d+\.rxdata", r"MapInfos\.rxdata", r"Tilesets\.rxdata"]


class Project:
    """Everything loaded from one src/tiled folder."""

    def __init__(self, paths):
        ## config.Paths
        self.paths = paths
        if not paths.exists():
            raise TiledError("%s doesn't exist. Run `make import-rxdata` (or create the first map with "
                             "the Tiled extension) first." % paths.rel(paths.registry))
        ## Map registry.
        self.registry = Registry.load(paths.registry)
        ## Combined tileset ids.
        self.tileset_registry = TilesetRegistry(paths.tileset_registry)
        ## Terrain tag names.
        self.tags = TerrainTags()
        ## Encounter type ids.
        self.encounter_types = config.encounter_types()
        ## Metadata fields.
        self.metadata_fields = pbsmaps.metadata_fields()
        ## .tsj cache (path -> JSON) shared by every map.
        self.tsj_cache = {}
        ## TilesetInfo cache.
        self.tileset_infos = {}
        ## Combined tilesets by id.
        self.combined = {}
        ## Template cache.
        self.templates = {}
        ## (passages, priorities, terrain tags) by combined tileset id.
        self.tables = {}

    def tileset_info(self, path):
        if path not in self.tileset_infos:
            self.tileset_infos[path] = TilesetInfo(path, self.tsj_cache.get(path))
        return self.tileset_infos[path]

    def tile_tables(self, combined):
        """@return (passages, priorities, terrain tags) of a combined tileset, cached"""
        if combined.id not in self.tables:
            self.tables[combined.id] = combined.tables(self.tags)
        return self.tables[combined.id]

    def rel_tileset(self, path):
        return os.path.relpath(path, self.paths.tilesets).replace(os.sep, "/")


class MapResult:
    """One compiled map."""

    def __init__(self, entry, path):
        self.entry = entry
        self.path = path
        self.ir = None
        self.spawns = {}
        self.metadata = None
        self.encounters = []
        self.explicit = []
        self.atmosphere = None
        ## stairs.StairMap (terrain and passability for the stair rules).
        self.stair_map = None


#===============================================================================
# One map
#===============================================================================
def compile_map(project, entry, problems):
    """Compiles one registry entry. @return MapResult (ir None on fatal errors)"""
    path = project.registry.map_path(entry)
    rel = project.paths.rel(path)
    result = MapResult(entry, path)
    if not os.path.isfile(path):
        problems.error(project.paths.rel(project.registry.path), "map %d" % entry["id"],
                       "%s doesn't exist" % entry["file"])
        return result
    try:
        data = load_json(path)
    except TiledError as e:
        problems.error(rel, "", str(e))
        return result
    fatal = False
    if data.get("orientation", "orthogonal") != "orthogonal":
        problems.error(rel, "", "the map is %s; only orthogonal maps are supported" % data.get("orientation"))
        fatal = True
    if data.get("infinite"):
        problems.error(rel, "", "infinite maps aren't supported (Map > Map Properties > Infinite)")
        fatal = True
    if data.get("tilewidth") != TILE or data.get("tileheight") != TILE:
        problems.error(rel, "", "tiles must be %dx%d (they're %sx%s)" % (TILE, TILE, data.get("tilewidth"),
                                                                       data.get("tileheight")))
        fatal = True
    width, height = data.get("width", 0), data.get("height", 0)
    if width <= 0 or height <= 0:
        problems.error(rel, "", "the map has no size")
        fatal = True
    if fatal:
        return result

    # Tilesets and numbering
    try:
        tilesets = map_tilesets(data, path, project.tsj_cache)
    except TiledError as e:
        problems.error(rel, "tilesets", str(e))
        return result
    regular, autotiles, kinds = [], [], {}
    for ts in tilesets:
        if ts.source is None:
            problems.error(rel, "tileset %r" % ts.data.get("name"),
                           "embedded tilesets aren't supported; export it as a .tsj next to the others")
            fatal = True
            continue
        info = project.tileset_info(ts.source)
        trel = project.paths.rel(ts.source)
        if info.kind != "preview" and (ts.data.get("tilewidth") != TILE or ts.data.get("tileheight") != TILE):
            problems.error(trel, "", "tiles must be %dx%d" % (TILE, TILE))
            fatal = True
        if info.kind == "preview":
            kinds[ts.firstgid] = ("preview", None, info)
        elif info.kind == "autotile":
            kinds[ts.firstgid] = ("autotile", len(autotiles), info)
            autotiles.append(info)
        else:
            if not ts.data.get("image"):
                problems.error(trel, "", "image collection tilesets can't be used for tiles")
                fatal = True
            kinds[ts.firstgid] = ("tileset", len(regular), info)
            regular.append(info)
    if len(autotiles) > AUTOTILE_SLOTS:
        problems.error(rel, "tilesets", "a map can use at most %d autotiles (it uses %d)"
                       % (AUTOTILE_SLOTS, len(autotiles)))
        fatal = True
    if fatal:
        return result
    reg_entry = project.tileset_registry.get(
        [project.rel_tileset(t.path) for t in regular], [project.rel_tileset(t.path) for t in autotiles],
        " + ".join([t.name for t in regular] + ([] if regular else [t.name for t in autotiles])) or "Empty")
    combined = project.combined.get(reg_entry["id"])
    if combined is None:
        combined = Combined(reg_entry, regular, autotiles)
        project.combined[reg_entry["id"]] = combined

    def rmxp_id(gid):
        """@return RMXP id, or raises TiledError"""
        ts = tileset_for_gid(tilesets, gid)
        if ts is None:
            raise TiledError("gid %d isn't in any of the map's tilesets" % gid)
        kind, index, info = kinds[ts.firstgid]
        local = gid - ts.firstgid
        if kind == "preview":
            raise TiledError("tiles from the event preview tileset %r can't be painted" % info.name)
        if kind == "autotile" and local >= AUTOTILE_TILES:
            raise TiledError("autotile %r: only its first %d tiles can be painted (the others are "
                             "animation frames)" % (info.name, AUTOTILE_TILES))
        return combined.rmxp_id(index, local, kind == "autotile")

    # Tile layers, flattened. With 3 layers or fewer, layer k stays RMXP
    # layer k; with more, each tile's stack is packed bottom to top.
    cells = [[] for _ in range(width * height)]
    tile_layers = [l for l, _ in iter_layers(data.get("layers", [])) if l.get("type") == "tilelayer"]
    keep_layers = len(tile_layers) <= RMXP_LAYERS
    for layer_index, (layer, parents) in enumerate((l, ()) for l in tile_layers):
        where = "layer %r" % layer.get("name")
        if layer.get("width") != width or layer.get("height") != height or layer.get("x", 0) or layer.get("y", 0):
            problems.error(rel, where, "tile layers must cover the whole map")
            continue
        if layer.get("offsetx") or layer.get("offsety"):
            problems.warning(rel, where, "layer offsets are ignored")
        try:
            gids = layer_gids(layer)
        except TiledError as e:
            problems.error(rel, where, str(e))
            continue
        reported = {"flip": 0, "bad": 0}
        for i, raw in enumerate(gids):
            if not raw:
                continue
            gid, flags = split_gid(raw)
            x, y = i % width, i // width
            if flags:
                reported["flip"] += 1
                if reported["flip"] <= MAX_TILE_PROBLEMS:
                    problems.error(rel, "%s, tile %d,%d" % (where, x, y),
                                   "flipped or rotated tiles aren't supported")
                continue
            try:
                tid = rmxp_id(gid)
                if keep_layers:
                    cells[i].extend([0] * (layer_index - len(cells[i])))
                cells[i].append(tid)
            except TiledError as e:
                reported["bad"] += 1
                if reported["bad"] <= MAX_TILE_PROBLEMS:
                    problems.error(rel, "%s, tile %d,%d" % (where, x, y), str(e))
        for kind, count in reported.items():
            if count > MAX_TILE_PROBLEMS:
                problems.error(rel, where, "... and %d more %s tiles" % (count - MAX_TILE_PROBLEMS,
                                                                         "flipped" if kind == "flip" else "invalid"))
    tile_data = [0] * (width * height * RMXP_LAYERS)
    crowded = 0
    for i, stack in enumerate(cells):
        if len([t for t in stack if t]) > RMXP_LAYERS:
            crowded += 1
            if crowded <= MAX_TILE_PROBLEMS:
                problems.error(rel, "tile %d,%d" % (i % width, i // width),
                               "%d tiles are stacked here; RPG Maker XP maps hold at most %d per tile "
                               "(merge or remove layers)" % (len(stack), RMXP_LAYERS))
            continue
        if not keep_layers:
            stack = [t for t in stack if t]
        for z, tid in enumerate(stack):
            tile_data[i + z * width * height] = tid
    if crowded > MAX_TILE_PROBLEMS:
        problems.error(rel, "", "... and %d more tiles with more than %d tiles stacked"
                       % (crowded - MAX_TILE_PROBLEMS, RMXP_LAYERS))

    # Events and spawns
    def tile_ref(ref):
        name, sep, local = str(ref).rpartition(":")
        if not sep or not local.isdigit():
            raise TiledError("tile must be 'tileset:number', not %r" % ref)
        for ts in tilesets:
            info = kinds.get(ts.firstgid)
            if info and info[2].name == name or (ts.source and os.path.splitext(os.path.basename(ts.source))[0] == name):
                return rmxp_id(ts.firstgid + int(local))
        raise TiledError("tile %r: the map has no tileset named %r" % (ref, name))

    event_irs, ids, positions = [], {}, {}
    map_params = {}
    for layer, raw_obj in events.map_objects(data):
        obj = events.resolve_template(raw_obj, path, project.templates)
        p = props(obj)
        if events.is_spawn(obj):
            x, y, aligned = events.object_tile(obj)
            name = obj.get("name", "")
            if not name:
                problems.error(rel, "spawn object %d" % obj.get("id", 0), "spawns need a name")
                continue
            if name in result.spawns:
                problems.error(rel, "spawn %r" % name, "two spawns have this name")
            direction = {v: k for k, v in config.DIRECTIONS.items()}.get(p.get("direction", "retain"), 0)
            result.spawns[name] = [x, y, direction]
            continue
        if not events.is_event(obj):
            continue
        event_id = p.get("event_id") or obj.get("id")
        where = "event %d %r" % (event_id, obj.get("name", ""))
        x, y, aligned = events.object_tile(obj)
        if not aligned:
            problems.warning(rel, where, "isn't on the tile grid (placed at %d,%d)" % (x, y))
        if not (0 <= x < width and 0 <= y < height):
            problems.error(rel, where, "is outside the map")
            continue
        if event_id in ids:
            problems.error(rel, where, "event id %d is also used by %r" % (event_id, ids[event_id]))
            continue
        ids[event_id] = obj.get("name", "")
        if (x, y) in positions:
            problems.warning(rel, where, "is on the same tile as event %d" % positions[(x, y)])
        positions[(x, y)] = event_id
        names = events.page_names(p)
        types = prop_types(obj)
        for n in names:
            if types[n][1] not in ("", events.PAGE_CLASS):
                problems.error(rel, where, "%s must be an %s property" % (n, events.PAGE_CLASS))
        pages = [events.page_to_settings(p[n], tile_ref, problems, rel, "%s %s" % (where, n)) for n in names]
        if not pages:
            pages = [events.page_to_settings({}, tile_ref, problems, rel, where)]
        script = events.event_script_path(path, obj)
        if script and not os.path.isfile(script):
            problems.error(rel, where, "its script %s doesn't exist" % project.paths.rel(script))
            script = None
        params = events.event_params(obj)
        params["_where"] = "%s %s" % (rel, where)
        event_irs.append({"id": event_id, "name": obj.get("name", ""), "x": x, "y": y, "pages": pages,
                          "script": script, "params": params})

    # Sideways stairs
    result.stair_map = stairs.StairMap(width, height, tile_data, RMXP_LAYERS, project.tile_tables(combined),
                                       project.tags)
    stairs.check_map(result.stair_map, result.spawns, event_irs, problems, rel)

    # Map properties
    mp = props(data)
    for name, value in mp.items():
        if name == "metadata":
            result.metadata = pbsmaps.props_to_metadata(entry["id"], value, project.metadata_fields, problems, rel)
        elif name == pbsmaps.ENCOUNTERS or name.startswith(pbsmaps.ENCOUNTERS + "_v"):
            enc = pbsmaps.props_to_encounters(entry["id"], name, value, project.encounter_types, problems, rel)
            if enc:
                result.encounters.append(enc)
        elif name == "connections":
            conns, errors = connections.parse_explicit(value, project.registry.name_to_id())
            for e in errors:
                problems.error(rel, "connections", e)
            result.explicit = [[entry["id"]] + c for c in conns]
        elif name == "atmosphere":
            result.atmosphere = value or None
    local_layers = atmosphere.map_layers(data, path, problems)
    map_params["layers"] = local_layers

    def audio(name):
        v = mp.get(name) or {}
        return {"name": v.get("name", ""), "volume": v.get("volume", 100 if name == "bgm" else 80),
                "pitch": v.get("pitch", 100)}

    result.ir = {
        "width": width, "height": height, "tileset_id": combined.id,
        "autoplay_bgm": bool(mp.get("autoplay_bgm")), "bgm": audio("bgm"),
        "autoplay_bgs": bool(mp.get("autoplay_bgs")), "bgs": audio("bgs"),
        "encounter_list": [], "encounter_step": mp.get("encounter_step", 30),
        "data": tile_data, "events": sorted(event_irs, key=lambda e: e["id"]),
    }
    result.local_atmosphere = local_layers
    return result


#===============================================================================
# The whole project
#===============================================================================
def run_ruby(script, payload, ruby="ruby"):
    """Runs a Ruby helper with a JSON file argument. @return parsed stdout JSON"""
    fd, tmp = tempfile.mkstemp(prefix="tiled_ir_", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(payload, f)
        proc = subprocess.run([ruby, os.path.join(config.RUBY_DIR, script), tmp],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    finally:
        os.remove(tmp)
    out = proc.stdout.decode("utf-8", "replace").strip()
    try:
        return json.loads(out.splitlines()[-1]) if out else {"errors": [], "written": []}
    except (json.JSONDecodeError, IndexError):
        raise TiledError("%s failed:\n%s%s" % (script, out, proc.stderr.decode("utf-8", "replace")))


def compile_project(paths, out_data=None, out_graphics=None, overlay=None, check_only=False,
                    ruby="ruby", force=False, log=print):
    """Validates and (unless check_only) compiles a Tiled source folder.

    @param out_data folder for the .rxdata files (build/Data)
    @param out_graphics folder for generated graphics (build/Graphics)
    @param overlay folder for the PBS JSON overlay (build/.tiled/pbs)
    @return Problems
    """
    problems = Problems()
    project = Project(paths)
    results = [compile_map(project, e, problems) for e in project.registry.entries]
    ok = [r for r in results if r.ir is not None]

    # Registry checks
    seen_files = {}
    for e in project.registry.entries:
        if e["file"] in seen_files:
            problems.error(paths.rel(paths.registry), "map %d" % e["id"], "uses the same file as map %d"
                           % seen_files[e["file"]])
        seen_files[e["file"]] = e["id"]
        if e.get("parent") and not project.registry.by_id(e["parent"]):
            problems.warning(paths.rel(paths.registry), "map %d" % e["id"], "its parent %d doesn't exist" % e["parent"])

    # World and connections
    placed, world_problems = connections.load_world(paths.world, project.registry)
    for file, message in world_problems:
        problems.error(paths.rel(paths.world), file, message)
    sizes = {r.entry["id"]: (r.ir["width"], r.ir["height"]) for r in ok}
    for p in placed:
        if p.map_id in sizes and (p.width, p.height) != sizes[p.map_id]:
            problems.warning(paths.rel(paths.world), "map %d" % p.map_id,
                             "the world has an old size for this map (reopen the world in Tiled to update it)")
            p.width, p.height = sizes[p.map_id]
    for i, a in enumerate(placed):
        for b in placed[i + 1:]:
            if connections.overlapping(a, b):
                problems.error(paths.rel(paths.world), "maps %d and %d" % (a.map_id, b.map_id),
                               "overlap in the world")
    conns = connections.merge(connections.world_connections(placed), [c for r in ok for c in r.explicit])

    # Atmospheres
    groups = atmosphere.compile_groups(atmosphere.load_groups(paths.atmospheres), problems)
    atmosphere_maps = {}
    for r in ok:
        if r.atmosphere and r.atmosphere not in groups:
            problems.error(paths.rel(r.path), "atmosphere", "no atmosphere group named %r in %s"
                           % (r.atmosphere, paths.rel(paths.atmospheres)))
        if r.atmosphere or r.local_atmosphere:
            atmosphere_maps[r.entry["id"]] = {"group": r.atmosphere if r.atmosphere in groups else None,
                                              "layers": r.local_atmosphere}

    # Tileset checks
    for info in project.tileset_infos.values():
        if info.kind == "tileset" and not info.has_tile_data():
            problems.warning(paths.rel(info.path), "", "no tile has TileData, so every tile is passable "
                             "with priority 0 (set passage and terrain tags in Tiled's tileset editor)")
        if info.kind == "autotile" and os.path.isdir(config.GRAPHICS):
            name = info.autotile_name()
            if not any(os.path.isfile(os.path.join(config.GRAPHICS, "Autotiles", name + ext)) for ext in (".png",)):
                problems.error(paths.rel(info.path), "autotile", "Graphics/Autotiles/%s.png not found in "
                               "src/assets/graphics" % name)
    tileset_irs = [project.combined[k].ir(project.tags, problems) for k in sorted(project.combined)]

    # Common events and system
    common = []
    if os.path.isdir(paths.common_events):
        for name in sorted(os.listdir(paths.common_events)):
            if name.endswith(".rb"):
                common.append({"path": os.path.join(paths.common_events, name)})
    system = load_json(paths.system) if os.path.isfile(paths.system) else None
    stairs.check_start(system, ok, problems, paths.rel(paths.system))

    spawns = {str(r.entry["id"]): r.spawns for r in ok}
    ir = {
        "out_dir": out_data or "", "check_only": check_only or not out_data, "halve_pictures": True,
        "mapinfos": project.registry.mapinfos(),
        "maps": {str(r.entry["id"]): r.ir for r in ok},
        "map_ids": project.registry.name_to_id(), "spawns": spawns,
        "tilesets": tileset_irs, "common_events": common if os.path.isdir(paths.common_events) else None,
        "system": system,
        "atmospheres": atmosphere.runtime_data(groups, atmosphere_maps, atmosphere.world_positions(placed)),
    }
    if not ok and project.registry.entries:
        return problems

    # Event scripts are evaluated (and data written) by Ruby. Skip it when
    # nothing changed since the last successful build.
    digest = _digest(ir)
    stamp = os.path.join(os.path.dirname(overlay), "last_build.sha1") if overlay else None
    if not check_only and out_data and stamp and not force and os.path.isfile(stamp) and \
            open(stamp).read() == digest and all(os.path.isfile(os.path.join(out_data, n))
                                                 for n in ("MapInfos.rxdata", "Tilesets.rxdata")):
        log("Tiled: %d maps up to date." % len(ok))
    elif problems.errors() and not check_only:
        pass   # don't write anything when the sources have errors
    else:
        report = run_ruby("rxdata_build.rb", ir, ruby)
        for e in report.get("errors", []):
            line = ":%s" % e["line"] if e.get("line") else ""
            where = e.get("event") or ""
            problems.error(paths.rel(e["file"] or "") + line, where, e["message"])
        if not check_only and out_data and not report.get("errors"):
            write_if_changed(os.path.join(out_data, "tiled_build.dat"), _marker())
            if stamp:
                write_if_changed(stamp, digest)
            log("Tiled: compiled %d maps, %d tilesets, %d common events (%d data files changed)."
                % (len(ok), len(tileset_irs), len(common), len(report.get("written", []))))

    if check_only or problems.errors():
        if project.tileset_registry.changed and not check_only:
            project.tileset_registry.save()
        return problems

    if project.tileset_registry.changed:
        project.tileset_registry.save()
        log("Tiled: new tileset combinations were added to %s; commit it so tileset ids stay the same."
            % paths.rel(paths.tileset_registry))
    if out_graphics:
        for combined in project.combined.values():
            try:
                written = combined.write_image(out_graphics, force)
                if written:
                    log("Tiled: wrote %s" % os.path.relpath(written))
            except (TiledError, OSError) as e:
                problems.error(paths.rel(paths.tileset_registry), "tileset %d" % combined.id, str(e))
    if overlay:
        pbsmaps.copy_pbs_tree(config.PBS_SRC, overlay)
        pbsmaps.write_overlay(overlay, [r.metadata for r in ok if r.metadata],
                              [e for r in ok for e in r.encounters], conns)
        owned = list(OWNED_PATTERNS)
        if ir["common_events"] is not None:
            owned.append(r"CommonEvents\.rxdata")
        if system is not None:
            owned.append(r"System\.rxdata")
        write_if_changed(os.path.join(os.path.dirname(overlay), "owned.txt"), "\n".join(owned) + "\n")
    return problems


def _digest(ir):
    """A hash of everything a build depends on (IR, scripts, Ruby helpers)."""
    h = hashlib.sha1(json.dumps(ir, sort_keys=True).encode("utf-8"))
    files = set()
    for m in ir["maps"].values():
        for e in m["events"]:
            if e.get("script"):
                files.add(e["script"])
    for c in ir.get("common_events") or []:
        files.add(c["path"])
    for name in sorted(os.listdir(config.RUBY_DIR)):
        files.add(os.path.join(config.RUBY_DIR, name))
    for path in sorted(files):
        if os.path.isfile(path):
            with open(path, "rb") as f:
                h.update(path.encode("utf-8"))
                h.update(f.read())
    return h.hexdigest()


def _marker():
    """Content of Data/tiled_build.dat: Marshal of the string "tiled"."""
    return b"\x04\x08I\"\x0atiled\x06:\x06ET"
