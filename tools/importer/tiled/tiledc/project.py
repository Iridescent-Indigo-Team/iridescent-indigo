"""@package tiledc.project
Writes src/tiled/pokessentials.tiled-project: the Tiled project with the
custom types Pokessentials uses (event pages, tile data, map metadata,
encounters, atmospheres). Enums are read from the engine sources (terrain
tags, encounter types, weather...) and the map metadata class from the PBS
JSON Schema, so `make tiled-project` keeps them in step with the game.
"""

import os

from . import config, events, pbsmaps
from .tiledio import load_json, save_json
from .tiles import DEFAULT_TILE_DATA

## Colours of the classes in Tiled.
CLASS_COLOR = "#ff3b82c4"


def _member(name, value, ptype=None, enum=None, cls=None):
    if cls:
        return {"name": name, "propertyType": cls, "type": "class", "value": value or {}}
    if enum:
        return {"name": name, "propertyType": enum, "type": "string", "value": value}
    if ptype is None:
        ptype = "bool" if isinstance(value, bool) else "int" if isinstance(value, int) else \
            "float" if isinstance(value, float) else "string"
    return {"name": name, "type": ptype, "value": value}


def property_types():
    """Every custom type, in a stable order."""
    types = []

    def enum(name, values):
        types.append({"name": name, "storageType": "string", "type": "enum", "values": list(values),
                      "valuesAsFlags": False})

    def cls(name, members, use_as, color=CLASS_COLOR):
        types.append({"color": color, "drawFill": True, "members": members, "name": name, "type": "class",
                      "useAs": use_as})

    enum("Direction", ["down", "left", "right", "up"])
    enum("SpawnDirection", ["retain", "down", "left", "right", "up"])
    enum("Trigger", config.TRIGGERS)
    enum("MoveType", config.MOVE_TYPES)
    enum("Blend", config.BLEND_TYPES)
    enum("TerrainTag", [name for _, name in config.terrain_tags()])
    enum("AtmosphereZ", ["above", "below"])

    # Metadata enums and nested classes, from the PBS schema
    fields = pbsmaps.metadata_fields()
    enums_done = set(t["name"] for t in types)
    nested = []
    meta_members = []

    def enum_name(field, values):
        name = "".join(part.capitalize() for part in field.split("_"))
        if field == "battle_environment":
            name = "Environment"
        if name not in enums_done:
            enum(name, values)
            enums_done.add(name)
        return name

    for name, kind, extra in fields:
        if kind == "bool":
            meta_members.append(_member(name, False))
        elif kind == "int":
            meta_members.append(_member(name, 0))
        elif kind == "enum":
            meta_members.append(_member(name, extra[0], enum=enum_name(name, extra)))
        elif kind == "object":
            sub = []
            for m, mk, mextra in extra:
                if mk == "enum":
                    sub.append(_member(m, mextra[0], enum=enum_name(m, mextra)))
                elif mk == "int":
                    sub.append(_member(m, -1))
                elif mk == "bool":
                    sub.append(_member(m, False))
                else:
                    sub.append(_member(m, ""))
            nested.append((pbsmaps.nested_class_name(name), sub))
            meta_members.append(_member(name, {}, cls=pbsmaps.nested_class_name(name)))
        else:
            meta_members.append(_member(name, ""))
    for name, sub in nested:
        cls(name, sub, ["property"])
    cls("MapMetadata", meta_members, ["property"])

    cls("EncounterTable", [_member("slots", ""), _member("step_chance", -1)], ["property"])
    cls("Encounters", [_member(t, {}, cls="EncounterTable") for t in config.encounter_types()], ["property"])
    cls("Audio", [_member("name", ""), _member("pitch", 100), _member("volume", 100)], ["property"])

    tile_members = []
    for k, v in DEFAULT_TILE_DATA.items():
        tile_members.append(_member(k, v, enum="TerrainTag" if k == "terrain_tag" else None))
    cls("TileData", tile_members, ["property", "tile", "tileset"])

    page = []
    enums_for_page = {"direction": "Direction", "blend": "Blend", "move_type": "MoveType", "trigger": "Trigger"}
    for k, v in events.PAGE_DEFAULTS.items():
        page.append(_member(k, v, enum=enums_for_page.get(k)))
    cls(events.PAGE_CLASS, page, ["property"])
    cls(config.CLASS_EVENT, [_member("event_id", 0), _member("page_0", {}, cls=events.PAGE_CLASS),
                             _member("script", "", "file")], ["object"], "#ff2fb84a")
    cls(config.CLASS_SPAWN, [_member("direction", "retain", enum="SpawnDirection")], ["object"], "#ffe0a020")

    cls("Map", [_member("atmosphere", ""), _member("autoplay_bgm", False), _member("autoplay_bgs", False),
                _member("bgm", {}, cls="Audio"), _member("bgs", {}, cls="Audio"), _member("connections", ""),
                _member("encounter_step", 30), _member("encounters", {}, cls="Encounters"),
                _member("metadata", {}, cls="MapMetadata")], ["map"])

    cls(config.CLASS_ATMOSPHERE_GROUP, [], ["layer"])
    cls("AtmosphereLayer", [_member("blend", "normal", enum="Blend"), _member("frame_duration", 5),
                            _member("frames", 1), _member("hue", 0), _member("scroll_x", 0.0),
                            _member("scroll_y", 0.0), _member("tone", "0,0,0,0"),
                            _member("z", "above", enum="AtmosphereZ"), _member("zoom_x", 100),
                            _member("zoom_y", 100)], ["layer"])
    cls(config.CLASS_AUTOTILE, [_member("autotile", ""), _member("TileData", {}, cls="TileData")], ["tileset"])
    cls(config.CLASS_PREVIEW, [], ["tileset"])
    for i, t in enumerate(types, start=1):
        t["id"] = i
    return types


def write_project(paths):
    """Writes or updates the project file, keeping settings made in Tiled.

    @return True if the file changed
    """
    doc = load_json(paths.project) if os.path.isfile(paths.project) else {}
    doc.setdefault("automappingRulesFile", "")
    doc.setdefault("commands", [])
    doc["compatibilityVersion"] = 1100
    doc["extensionsPath"] = "extensions"
    doc.setdefault("folders", ["."])
    doc["propertyTypes"] = property_types()
    return save_json(paths.project, doc)
