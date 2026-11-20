"""@package tiledc.events
Events on Tiled maps.

An event is an object of class "Event" on any object layer:
  * its position is the tile it starts on (the object's top-left corner, or
    bottom-left for tile objects, snapped to the 32px grid);
  * "event_id" (int) is the RMXP event id (self switches use it); the Tiled
    object id is used when it's missing;
  * "page_0", "page_1", ... (class EventPage) are the page settings:
    conditions, graphic, movement, options and trigger;
  * "script" (file) is the .rb file with the commands of each page
    (`page 0, [...]`), usually src/tiled/events/<map>/<id>_<name>.rb. Events
    placed from a template share the template's script;
  * any other custom property is a parameter the script reads with
    `param(:name)` (the item of an item ball, the target of a door, ...).

A "Spawn" object marks a named arrival point for `transfer(to:, spawn:)`;
its optional "direction" property is the direction the player faces.
"""

import json
import os
import re

from . import config
from .config import BLEND_TYPES, CLASS_EVENT, CLASS_SPAWN, DIRECTIONS, MOVE_TYPES, TILE, TRIGGERS
from .problems import TiledError
from .registry import slug
from .tiledio import iter_layers, make_prop, props, relpath, set_props, split_gid

## Page settings class.
PAGE_CLASS = "EventPage"
## Property names that aren't script parameters.
RESERVED = {"event_id", "script"}
## Default page settings (Tiled member form).
PAGE_DEFAULTS = {
    "switch1": 0, "switch2": 0, "variable": 0, "variable_value": 0, "self_switch": "",
    "graphic": "", "tile": "", "hue": 0, "direction": "down", "pattern": 0, "opacity": 255,
    "blend": "normal", "move_type": "fixed", "move_speed": 3, "move_frequency": 3,
    "walk_anime": True, "step_anime": False, "direction_fix": False, "through": False,
    "always_on_top": False, "trigger": "action",
}
## Header line of standalone event files.
STANDALONE_HEADER = "# @tiled-event "

_DIR_NUMBERS = {v: k for k, v in DIRECTIONS.items()}


def object_class(obj):
    """An object's class: "type" in Tiled 1.10+ files, "class" in 1.9 ones."""
    return obj.get("type") or obj.get("class") or ""


def is_event(obj):
    return object_class(obj) == CLASS_EVENT


def is_spawn(obj):
    return object_class(obj) == CLASS_SPAWN


def page_names(p):
    """The page property names of an object, in page order."""
    pages = [(int(m.group(1)), k) for k in p for m in [re.match(r"^page_(\d+)$", k)] if m]
    return [k for _, k in sorted(pages)]


def object_tile(obj):
    """The tile an object stands on. @return (x, y, aligned)

    Rectangle objects: their top-left corner. Tile objects (an event showing
    its graphic) are drawn standing on the tile: centred horizontally, with
    their bottom edge on the tile's bottom edge, like the game draws them.
    """
    x = obj.get("x", 0)
    y = obj.get("y", 0)
    if obj.get("gid"):
        x += obj.get("width", TILE) / 2.0 - TILE / 2.0
        y -= TILE
    tx, ty = int(round(x / TILE)), int(round(y / TILE))
    return tx, ty, abs(x - tx * TILE) < 0.5 and abs(y - ty * TILE) < 0.5


def object_layers(map_data):
    """Every object layer of a map (including those inside groups)."""
    return [layer for layer, _ in iter_layers(map_data.get("layers", [])) if layer.get("type") == "objectgroup"]


def map_objects(map_data):
    """Every object of a map. @return list of (layer, object)"""
    return [(layer, obj) for layer in object_layers(map_data) for obj in layer.get("objects", [])]


def resolve_template(obj, map_path, cache):
    """An object merged with its template (template properties first)."""
    if "template" not in obj:
        return obj
    from .tiledio import load_json
    path = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(map_path)), obj["template"]))
    if path not in cache:
        cache[path] = load_json(path)
    tpl = dict(cache[path].get("object", {}))
    merged = dict(tpl)
    merged.update({k: v for k, v in obj.items() if k != "properties" and not (k == "name" and not v)})
    base = {p["name"]: p for p in tpl.get("properties", [])}
    for p in obj.get("properties", []):
        if p["name"] in base and isinstance(base[p["name"]].get("value"), dict) and isinstance(p.get("value"), dict):
            value = dict(base[p["name"]]["value"])
            value.update(p["value"])
            p = dict(p, value=value)
        base[p["name"]] = p
    merged["properties"] = list(base.values())
    own = {p["name"] for p in obj.get("properties", [])}
    if "script" not in own:
        merged["_script_base"] = os.path.dirname(path)
    return merged


#===============================================================================
# Page settings
#===============================================================================
def page_to_settings(value, tile_resolver, problems, path, where):
    """EventPage members -> RMXP page settings for the Ruby back end.

    @param tile_resolver function "tileset:local" -> RMXP tile id (or raises)
    """
    v = dict(PAGE_DEFAULTS)
    v.update(value or {})
    unknown = set(value or {}) - set(PAGE_DEFAULTS)
    for name in sorted(unknown):
        problems.warning(path, where, "unknown page setting %r is ignored" % name)

    def pick(name, names):
        if v[name] in names:
            return names.index(v[name])
        problems.error(path, where, "%s must be one of %s, not %r" % (name, ", ".join(n or '""' for n in names), v[name]))
        return 0

    tile_id = 0
    if v["tile"]:
        try:
            tile_id = tile_resolver(v["tile"])
        except TiledError as e:
            problems.error(path, where, str(e))
    direction = _DIR_NUMBERS.get(v["direction"])
    if direction in (None, 0):
        problems.error(path, where, "direction must be down, left, right or up, not %r" % v["direction"])
        direction = 2
    if v["self_switch"] not in config.SELF_SWITCHES:
        problems.error(path, where, "self_switch must be A, B, C, D or empty")
    return {
        "switch1": v["switch1"], "switch2": v["switch2"], "variable": v["variable"],
        "variable_value": v["variable_value"],
        "self_switch": v["self_switch"] if v["self_switch"] in config.SELF_SWITCHES else "",
        "tile_id": tile_id, "character_name": v["graphic"], "character_hue": v["hue"],
        "direction": direction, "pattern": v["pattern"], "opacity": v["opacity"],
        "blend_type": pick("blend", BLEND_TYPES), "move_type": pick("move_type", MOVE_TYPES),
        "move_speed": v["move_speed"], "move_frequency": v["move_frequency"],
        "walk_anime": bool(v["walk_anime"]), "step_anime": bool(v["step_anime"]),
        "direction_fix": bool(v["direction_fix"]), "through": bool(v["through"]),
        "always_on_top": bool(v["always_on_top"]), "trigger": pick("trigger", TRIGGERS),
    }


def settings_to_page(s, tile_name):
    """RMXP page settings (from the importer) -> EventPage members that
    differ from the defaults.

    @param tile_name function RMXP tile id -> "tileset:local"
    """
    v = {
        "switch1": s["switch1"], "switch2": s["switch2"], "variable": s["variable"],
        "variable_value": s["variable_value"], "self_switch": s["self_switch"],
        "graphic": s["character_name"], "tile": tile_name(s["tile_id"]) if s["tile_id"] else "",
        "hue": s["character_hue"], "direction": DIRECTIONS.get(s["direction"], "down"),
        "pattern": s["pattern"], "opacity": s["opacity"],
        "blend": BLEND_TYPES[s["blend_type"]] if s["blend_type"] < len(BLEND_TYPES) else "normal",
        "move_type": MOVE_TYPES[s["move_type"]] if s["move_type"] < len(MOVE_TYPES) else "fixed",
        "move_speed": s["move_speed"], "move_frequency": s["move_frequency"],
        "walk_anime": s["walk_anime"], "step_anime": s["step_anime"],
        "direction_fix": s["direction_fix"], "through": s["through"],
        "always_on_top": s["always_on_top"],
        "trigger": TRIGGERS[s["trigger"]] if s["trigger"] < len(TRIGGERS) else "action",
    }
    return {k: val for k, val in v.items() if val != PAGE_DEFAULTS[k]}


def page_props(pages):
    """Property entries for a list of EventPage member dicts."""
    return [make_prop("page_%d" % i, page, "class", PAGE_CLASS) for i, page in enumerate(pages)]


#===============================================================================
# Objects
#===============================================================================
def event_script_path(map_path, obj):
    """Absolute path of an event's script, or None. A script inherited from a
    template is relative to the template file."""
    script = props(obj).get("script")
    if not script:
        return None
    base = obj.get("_script_base") or os.path.dirname(os.path.abspath(map_path))
    return os.path.normpath(os.path.join(base, script))


def event_params(obj):
    """Script parameters: custom properties that aren't page settings."""
    p = props(obj)
    return {k: v for k, v in p.items() if k not in RESERVED and not re.match(r"^page_\d+$", k)}


def new_event_object(object_id, event_id, name, x, y, pages, script_rel=None, gid=None):
    """A new Tiled event object.

    @param pages list of EventPage member dicts
    """
    # Tiled 1.10+ saves an object's class as "type" ("class" in 1.9 only).
    obj = {"height": TILE, "id": object_id, "name": name, "rotation": 0,
           "type": CLASS_EVENT, "visible": True, "width": TILE, "x": x * TILE, "y": y * TILE}
    if gid:
        obj["gid"] = gid
        obj["y"] = (y + 1) * TILE   # tile objects are anchored at their bottom
    entries = [make_prop("event_id", event_id, "int")] + page_props(pages)
    if script_rel:
        entries.append(make_prop("script", script_rel, "file"))
    set_props(obj, entries)
    return obj


def events_folder(paths, map_path):
    """Folder for a map's event scripts."""
    return os.path.join(paths.events, os.path.splitext(os.path.basename(map_path))[0])


def script_file_name(event_id, name):
    return "%03d_%s.rb" % (event_id, slug(name) if name else "event")


#===============================================================================
# Standalone event files (export-events / import-events)
#===============================================================================
def export_event(obj, script_text):
    """A standalone .rb for one event: a header line with its settings, then
    its commands."""
    p = props(obj)
    header = {"name": obj.get("name", ""), "pages": [p[k] for k in page_names(p)],
              "params": event_params(obj)}
    tx, ty, _ = object_tile(obj)
    header["x"], header["y"] = tx, ty
    return STANDALONE_HEADER + json.dumps(header, ensure_ascii=False) + "\n" + (script_text or "")


def read_standalone(text):
    """Parses a standalone event file. @return (header dict, script text)"""
    first, _, rest = text.partition("\n")
    if not first.startswith(STANDALONE_HEADER):
        raise TiledError("not an exported event (the first line must start with %r)" % STANDALONE_HEADER)
    return json.loads(first[len(STANDALONE_HEADER):]), rest


def next_ids(map_data):
    """@return (next Tiled object id, next free event id)"""
    used_events = [0]
    for _, obj in map_objects(map_data):
        if is_event(obj):
            used_events.append(props(obj).get("event_id") or obj.get("id", 0))
    return map_data.get("nextobjectid", 1), max(used_events) + 1


def first_object_layer(map_data, name="Events"):
    """The map's "Events" object layer, created if needed."""
    for layer in object_layers(map_data):
        if layer.get("name") == name:
            return layer
    layer = {"draworder": "topdown", "id": map_data.get("nextlayerid", 1), "name": name, "objects": [],
             "opacity": 1, "type": "objectgroup", "visible": True, "x": 0, "y": 0}
    map_data["nextlayerid"] = layer["id"] + 1
    map_data.setdefault("layers", []).append(layer)
    return layer


def import_event(map_data, map_path, paths, text, x=None, y=None):
    """Adds a standalone event to a map. @return the new object"""
    header, script = read_standalone(text)
    object_id, event_id = next_ids(map_data)
    tx = header.get("x", 0) if x is None else x
    ty = header.get("y", 0) if y is None else y
    name = header.get("name", "")
    script_rel = None
    if script.strip():
        folder = events_folder(paths, map_path)
        os.makedirs(folder, exist_ok=True)
        script_path = os.path.join(folder, script_file_name(event_id, name))
        with open(script_path, "w", encoding="utf-8") as f:
            f.write(script)
        script_rel = relpath(script_path, map_path)
    obj = new_event_object(object_id, event_id, name, tx, ty, header.get("pages", [{}]), script_rel)
    params = header.get("params") or {}
    if params:
        set_props(obj, [make_prop(k, v) for k, v in params.items()])
    first_object_layer(map_data)["objects"].append(obj)
    map_data["nextobjectid"] = object_id + 1
    return obj


def gid_tileset_local(gid, tilesets):
    """@return (MapTileset, local id) of a gid, flags removed"""
    from .tiledio import tileset_for_gid
    plain, _ = split_gid(gid)
    ts = tileset_for_gid(tilesets, plain)
    return ts, (plain - ts.firstgid) if ts else None
