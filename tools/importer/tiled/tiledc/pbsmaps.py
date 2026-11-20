"""@package tiledc.pbsmaps
Map metadata, encounters and connections stored on Tiled maps, and the PBS
JSON the compiler makes from them.

On a map:
  * "metadata" (class MapMetadata): the map_metadata.txt entry. Its members
    come from the PBS JSON Schema, so every field the engine supports is
    there. Only members changed from their defaults are stored, and only
    those are written to PBS.
  * "encounters" (class Encounters), and "encounters_v1", "encounters_v2", ...
    for encounter versions: one EncounterTable member per encounter type, with
    "step_chance" (-1 = the type's default) and "slots", written as
    "60 TENTACOOL 14-19; 30 MANTYKE 15-16" (chance, species, level or range).
  * connections: from the world file (see connections.py).

The compiler writes these into a copy of src/pbs (build/.tiled/pbs), which
`make pbs` exports to build/PBS with the existing PBS tools, so their
validation and file format are reused unchanged.
"""

import os
import re
import shutil

import sys

from . import config
from .tiledio import load_json, write_if_changed

sys.path.insert(0, os.path.join(config.ROOT, "tools", "importer", "pbs"))
from pbsjson.store import dumps as _pbs_dumps  # noqa: E402  (same layout as src/pbs)


def save_json(path, value):
    """Writes JSON in the PBS tools' layout. @return True if changed"""
    return write_if_changed(path, _pbs_dumps(value) + "\n")

## Datasets the Tiled maps own.
MAP_DATASETS = ("map_metadata", "encounters", "map_connections")
## Property name of version 0 encounters; versions add "_v<n>".
ENCOUNTERS = "encounters"


def nested_class_name(prop):
    """Tiled class name for an object-valued metadata field."""
    return "MapMetadata_" + "".join(part.capitalize() for part in prop.split("_"))


def metadata_fields(schema=None):
    """The MapMetadata fields from the PBS JSON Schema.

    @return list of (name, kind, extra) where kind is "bool", "int", "string",
        "enum" (extra = values), "list" (comma separated strings) or "object"
        (extra = list of (member, kind, values))
    """
    schema = schema if schema is not None else config.map_metadata_schema()
    if not schema:
        return []
    fields = []
    for name, spec in schema.get("properties", {}).items():
        if name in ("$schema", "id"):
            continue
        fields.append((name,) + _kind(spec))
    return fields


def _kind(spec):
    t = spec.get("type")
    if "enum" in spec:
        return "enum", spec["enum"]
    if t == "boolean":
        return "bool", None
    if t == "integer":
        return "int", None
    if t == "array":
        return "list", None
    if t == "object":
        return "object", [(m,) + _kind(s) for m, s in spec.get("properties", {}).items()]
    return "string", None


def metadata_to_props(entry, fields):
    """A PBS JSON map_metadata entry -> the MapMetadata class value."""
    value = {}
    for name, kind, extra in fields:
        if name not in entry:
            continue
        v = entry[name]
        if kind == "list":
            value[name] = ", ".join(str(x) for x in v)
        else:
            value[name] = v
    return value


def props_to_metadata(map_id, value, fields, problems, path):
    """The MapMetadata class value -> a PBS JSON map_metadata entry (or None)."""
    if not value:
        return None
    entry = {"id": map_id}
    for name, kind, extra in fields:
        if name not in value:
            continue
        v = value[name]
        if kind == "bool":
            if v:
                entry[name] = True
        elif kind == "int":
            if v not in (None, 0, -1):
                entry[name] = v
        elif kind == "list":
            items = [s.strip() for s in str(v).split(",") if s.strip()]
            if items:
                entry[name] = items
        elif kind == "object":
            if not isinstance(v, dict) or not v:
                continue
            members = {}
            missing = []
            for m, mkind, mextra in extra:
                if m in v and v[m] != -1:
                    members[m] = v[m]
                elif mkind == "enum":
                    members[m] = mextra[0]       # Tiled doesn't store defaults
                elif mkind == "bool":
                    members[m] = False
                elif mkind == "string":
                    members[m] = ""
                else:
                    missing.append(m)
            if missing:
                problems.error(path, "metadata.%s" % name, "set every member (%s missing)" % ", ".join(missing))
                continue
            entry[name] = members
        elif kind == "enum" or kind == "string":
            if v not in (None, ""):
                entry[name] = v
    unknown = set(value) - {f[0] for f in fields}
    for name in sorted(unknown):
        problems.warning(path, "metadata", "unknown member %r is ignored" % name)
    return entry if len(entry) > 1 else None


#===============================================================================
# Encounters
#===============================================================================
_SLOT = re.compile(r"^\s*(\d+)\s*%?\s+([A-Za-z0-9_]+)\s+(\d+)(?:\s*-\s*(\d+))?\s*$")


def slots_to_text(slots):
    """Encounter slots -> "60 TENTACOOL 14-19; 30 MANTYKE 15"."""
    parts = []
    for s in slots:
        levels = str(s["min_level"])
        if s.get("max_level") is not None:
            levels += "-%d" % s["max_level"]
        parts.append("%d %s %s" % (s["chance"], s["species"], levels))
    return "; ".join(parts)


def text_to_slots(text, problems, path, where):
    """Parses slot text. @return list of slot dicts"""
    slots = []
    for raw in re.split(r"[;\n]", text or ""):
        if not raw.strip():
            continue
        m = _SLOT.match(raw)
        if not m:
            problems.error(path, where, "can't read encounter slot %r (expected 'chance SPECIES level' "
                           "or 'chance SPECIES min-max')" % raw.strip())
            continue
        slot = {"chance": int(m.group(1)), "species": m.group(2), "min_level": int(m.group(3))}
        if m.group(4):
            slot["max_level"] = int(m.group(4))
        slots.append(slot)
    return slots


def encounters_to_props(entry):
    """A PBS JSON encounters entry -> (property name, Encounters class value)."""
    name = ENCOUNTERS if not entry.get("version") else "%s_v%d" % (ENCOUNTERS, entry["version"])
    value = {}
    for t in entry.get("types", []):
        table = {"slots": slots_to_text(t.get("slots", []))}
        if t.get("step_chance") is not None:
            table["step_chance"] = t["step_chance"]
        value[t["type"]] = table
    return name, value


def props_to_encounters(map_id, prop_name, value, types, problems, path):
    """An Encounters class value -> a PBS JSON encounters entry (or None)."""
    version = 0
    if prop_name != ENCOUNTERS:
        m = re.match(r"^%s_v(\d+)$" % ENCOUNTERS, prop_name)
        if not m:
            return None
        version = int(m.group(1))
    entry = {"map": map_id}
    if version:
        entry["version"] = version
    entry["types"] = []
    order = list(types) + sorted(set(value or {}) - set(types))
    for t in order:
        if t not in (value or {}):
            continue
        if t not in types:
            problems.error(path, prop_name, "unknown encounter type %r" % t)
            continue
        table = value[t] or {}
        slots = text_to_slots(table.get("slots", ""), problems, path, "%s.%s" % (prop_name, t))
        if not slots:
            continue
        item = {"type": t}
        if table.get("step_chance") not in (None, -1):
            item["step_chance"] = table["step_chance"]
        item["slots"] = slots
        entry["types"].append(item)
    return entry if entry["types"] else None


#===============================================================================
# The PBS JSON overlay
#===============================================================================
def copy_pbs_tree(src, dst):
    """Copies src/pbs to dst, except the datasets the maps own. Files are only
    rewritten when they change; files no longer in src are removed."""
    wanted = set()
    for dirpath, dirnames, filenames in os.walk(src):
        rel_dir = os.path.relpath(dirpath, src)
        top = rel_dir.split(os.sep)[0]
        if top in MAP_DATASETS:
            continue
        for name in filenames:
            if rel_dir == "." and os.path.splitext(name)[0] in MAP_DATASETS:
                continue
            rel = os.path.normpath(os.path.join(rel_dir, name))
            wanted.add(rel)
            s, d = os.path.join(src, rel), os.path.join(dst, rel)
            if os.path.isfile(d) and os.path.getmtime(d) >= os.path.getmtime(s) and \
                    os.path.getsize(d) == os.path.getsize(s):
                continue
            os.makedirs(os.path.dirname(d), exist_ok=True)
            shutil.copy2(s, d)
    if os.path.isdir(dst):
        for dirpath, _, filenames in os.walk(dst):
            rel_dir = os.path.relpath(dirpath, dst)
            if rel_dir.split(os.sep)[0] in MAP_DATASETS:
                continue
            for name in filenames:
                rel = os.path.normpath(os.path.join(rel_dir, name))
                if rel not in wanted and not (rel_dir == "." and os.path.splitext(name)[0] in MAP_DATASETS):
                    os.remove(os.path.join(dst, rel))


def _schema_ref(depth, name):
    return "../" * depth + "_schema/" + name


def write_split(dst, dataset, entries):
    """Writes a split dataset (one JSON per entry plus _index.json).

    @param entries list of (stem, entry dict)
    """
    folder = os.path.join(dst, dataset)
    os.makedirs(folder, exist_ok=True)
    stems = []
    for stem, entry in entries:
        doc = {"$schema": _schema_ref(1, dataset + ".entry.schema.json")}
        doc.update(entry)
        save_json(os.path.join(folder, stem + ".json"), doc)
        stems.append(stem)
    for name in os.listdir(folder):
        if name.endswith(".json") and name != "_index.json" and name[:-5] not in stems:
            os.remove(os.path.join(folder, name))
    save_json(os.path.join(folder, "_index.json"),
              {"$schema": _schema_ref(1, "index.schema.json"),
               "files": [{"suffix": "", "bom": True, "entries": stems}]})


def write_overlay(dst, metadata, encounters, connections):
    """Writes the three map datasets into the overlay tree.

    @param metadata list of entries
    @param encounters list of entries
    @param connections list of [map, side, offset, other, other_side, other_offset]
    """
    write_split(dst, "map_metadata", [("map_%03d" % e["id"], e) for e in sorted(metadata, key=lambda e: e["id"])])
    enc = []
    for e in sorted(encounters, key=lambda e: (e["map"], e.get("version", 0))):
        stem = "map_%03d" % e["map"] + ("_%d" % e["version"] if e.get("version") else "")
        enc.append((stem, e))
    write_split(dst, "encounters", enc)
    entries = [{"map": c[0], "side": c[1], "offset": c[2], "other_map": c[3], "other_side": c[4],
                "other_offset": c[5]} for c in connections]
    save_json(os.path.join(dst, "map_connections.json"),
              {"$schema": _schema_ref(0, "map_connections.schema.json"),
               "files": [{"suffix": "", "bom": True, "entries": entries}]})


def read_pbs_maps(pbs_src):
    """Reads the three map datasets from a PBS JSON tree (for importing).

    @return (metadata entries, encounter entries, connection lists)
    """
    def split(dataset):
        folder = os.path.join(pbs_src, dataset)
        index = os.path.join(folder, "_index.json")
        if not os.path.isfile(index):
            return []
        result = []
        for f in load_json(index).get("files", []):
            for stem in f.get("entries", []):
                e = load_json(os.path.join(folder, stem + ".json"))
                e.pop("$schema", None)
                result.append(e)
        return result

    conns = []
    path = os.path.join(pbs_src, "map_connections.json")
    if os.path.isfile(path):
        for f in load_json(path).get("files", []):
            for c in f.get("entries", []):
                conns.append([c["map"], c["side"], c["offset"], c["other_map"], c["other_side"], c["other_offset"]])
    return split("map_metadata"), split("encounters"), conns


def remove_pbs_maps(pbs_src):
    """Deletes the map datasets from src/pbs once Tiled owns them.

    @return list of removed paths
    """
    removed = []
    for name in MAP_DATASETS:
        for path in (os.path.join(pbs_src, name), os.path.join(pbs_src, name + ".json")):
            if os.path.isdir(path):
                shutil.rmtree(path)
                removed.append(path)
            elif os.path.isfile(path):
                os.remove(path)
                removed.append(path)
    return removed


def stamp(path, text):
    """Writes a small marker file."""
    write_if_changed(path, text)
