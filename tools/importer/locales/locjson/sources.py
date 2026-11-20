"""@package locjson.sources
Gathers every English string the game can translate, with a stable key, the
CSV file it belongs in and the engine message table it compiles into.

- PBS data: the JSON in src/pbs (read with the PBS converter's loader).
- Script text: _INTL/_ISPRINTF literals in src/data and src/assets/plugins.
- Event text: the RMXP maps and common events (extract_events.rb).
"""

import hashlib
import json
import os
import re
import subprocess
import sys

from . import config as cfg
from . import messages as mt

#===============================================================================
# Strings
#===============================================================================
class SourceString:
    """One translatable English string."""

    def __init__(self, file, key, english, mtype, map_id=None, context="", noun=None, number="sg",
                 field=None, message=False):
        ## CSV file, relative to a language folder ("items.csv", "events/map003.csv").
        self.file = file
        ## Stable key, unique in the file.
        self.key = key
        ## The English text.
        self.english = english
        ## MessageTypes table.
        self.mtype = mtype
        ## Map id for event text (0 = common events), else None.
        self.map_id = map_id
        ## Where the string is used, for translators.
        self.context = context
        ## Noun group (an entry id) for strings that are nouns, else None.
        self.noun = noun
        ## "sg" or "pl" for nouns.
        self.number = number
        ## "file.field" for size checks ("items.description"), or None.
        self.field = field
        ## True if the text is shown in the message window.
        self.message = message
        ## Other keys whose English is the same (merged into this row).
        self.also = []

    @property
    def runtime_key(self):
        """(table, map id, key) the engine looks the translation up by."""
        return (self.mtype, self.map_id, mt.string_to_key(self.english))


def short_hash(text):
    """8 hex digits identifying a text."""
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:8]


def _slug(text):
    s = re.sub(r"[^A-Za-z0-9]+", "_", text).strip("_")
    return s[:40] or short_hash(text)


#===============================================================================
# PBS data
#===============================================================================
def _load_pbs(pbs_dir):
    if cfg.PBS_TOOL_DIR not in sys.path:
        sys.path.insert(0, cfg.PBS_TOOL_DIR)
    from pbsjson.config import Config as PbsConfig
    from pbsjson.store import load_json_tree
    return {d.name: d for d in load_json_tree(PbsConfig(), pbs_dir)}


def pbs_strings(pbs_dir=cfg.PBS_DIR):
    """Strings from the JSON game data. @return list of SourceString"""
    data = _load_pbs(pbs_dir)
    out = []

    def add(file, key, text, mtype, context, **kw):
        if isinstance(text, str) and text != "":
            out.append(SourceString(file, key, text, mtype, context=context, **kw))

    def entries(name):
        return list(data[name].entries()) if name in data else []

    for e in entries("types"):
        add("types.csv", "%s.name" % e["id"], e.get("real_name"), mt.TYPE_NAMES, "Type",
            noun=e["id"], field="types.name")
    for e in entries("abilities"):
        add("abilities.csv", "%s.name" % e["id"], e.get("real_name"), mt.ABILITY_NAMES, "Ability name",
            noun=e["id"], field="abilities.name")
        add("abilities.csv", "%s.description" % e["id"], e.get("real_description"), mt.ABILITY_DESCRIPTIONS,
            "Ability description", field="abilities.description")
    for e in entries("moves"):
        add("moves.csv", "%s.name" % e["id"], e.get("real_name"), mt.MOVE_NAMES, "Move name",
            noun=e["id"], field="moves.name")
        add("moves.csv", "%s.description" % e["id"], e.get("real_description"), mt.MOVE_DESCRIPTIONS,
            "Move description", field="moves.description")
    for e in entries("items"):
        i = e["id"]
        add("items.csv", "%s.name" % i, e.get("real_name"), mt.ITEM_NAMES, "Item name", noun=i,
            field="items.name")
        add("items.csv", "%s.name_plural" % i, e.get("real_name_plural"), mt.ITEM_NAME_PLURALS,
            "Item name (plural)", noun=i, number="pl", field="items.name_plural")
        add("items.csv", "%s.portion_name" % i, e.get("real_portion_name"), mt.ITEM_PORTION_NAMES,
            "Item portion name", noun=i + ":portion", field="items.portion_name")
        add("items.csv", "%s.portion_name_plural" % i, e.get("real_portion_name_plural"),
            mt.ITEM_PORTION_NAME_PLURALS, "Item portion name (plural)", noun=i + ":portion", number="pl",
            field="items.portion_name_plural")
        add("items.csv", "%s.description" % i, e.get("real_description"), mt.ITEM_DESCRIPTIONS,
            "Item description", field="items.description")
    for e in entries("pokemon"):
        i = e["id"]
        add("species.csv", "%s.name" % i, e.get("real_name"), mt.SPECIES_NAMES, "Species name", noun=i,
            field="species.name")
        add("species.csv", "%s.form_name" % i, e.get("real_form_name"), mt.SPECIES_FORM_NAMES, "Form name",
            field="species.form_name")
        add("species.csv", "%s.category" % i, e.get("real_category"), mt.SPECIES_CATEGORIES, "Category",
            field="species.category")
        add("species.csv", "%s.pokedex" % i, e.get("real_pokedex_entry"), mt.POKEDEX_ENTRIES,
            "Pokédex entry", field="species.pokedex")
    for e in entries("pokemon_forms"):
        i = "%s_%s" % (e["species"], e["form"])
        add("species.csv", "%s.form_name" % i, e.get("real_form_name"), mt.SPECIES_FORM_NAMES, "Form name",
            field="species.form_name")
        add("species.csv", "%s.category" % i, e.get("real_category"), mt.SPECIES_CATEGORIES, "Category",
            field="species.category")
        add("species.csv", "%s.pokedex" % i, e.get("real_pokedex_entry"), mt.POKEDEX_ENTRIES,
            "Pokédex entry", field="species.pokedex_form")
    for e in entries("ribbons"):
        add("ribbons.csv", "%s.name" % e["id"], e.get("real_name"), mt.RIBBON_NAMES, "Ribbon name",
            noun=e["id"], field="ribbons.name")
        add("ribbons.csv", "%s.description" % e["id"], e.get("real_description"), mt.RIBBON_DESCRIPTIONS,
            "Ribbon description", field="ribbons.description")
        # Title conferred by the ribbon/mark (PrefixTitle wins over Title, as
        # in the engine). Tokens such as /Owner/ must be kept as they are.
        title = e.get("real_prefix_title") or e.get("real_title")
        add("ribbons.csv", "%s.title" % e["id"], title, mt.RIBBON_TITLES, "Ribbon/mark title",
            field="ribbons.title")
    for e in entries("trainer_types"):
        add("trainer_types.csv", "%s.name" % e["id"], e.get("real_name"), mt.TRAINER_TYPE_NAMES,
            "Trainer type", noun=e["id"], field="trainer_types.name")
    for e in entries("trainers"):
        base = "%s.%s" % (e.get("trainer_type"), _slug(e.get("name", "")))
        if e.get("version"):
            base += ".%d" % e["version"]
        add("trainers.csv", base + ".name", e.get("name"), mt.TRAINER_NAMES, "Trainer name",
            field="trainers.name")
        add("trainers.csv", base + ".lose_text", e.get("real_lose_text"), mt.TRAINER_SPEECHES_LOSE,
            "Said when the trainer loses (battle message)", message=True)
        for n, pkmn in enumerate(e.get("pokemon", [])):
            add("trainers.csv", "%s.pokemon%d.nickname" % (base, n + 1), pkmn.get("real_name"),
                mt.POKEMON_NICKNAMES, "Nickname of %s" % pkmn.get("species"), field="trainers.nickname")
    for e in entries("map_metadata"):
        add("map_names.csv", "MAP%03d.name" % e["id"], e.get("real_name"), mt.MAP_NAMES, "Map name",
            field="map_names.name")
    for e in entries("town_map"):
        add("town_map.csv", "REGION%s.name" % e["id"], e.get("real_name"), mt.REGION_NAMES, "Region name",
            field="town_map.region")
        for p in e.get("point", []) or []:
            add("town_map.csv", "location.%s" % _slug(p.get("name") or ""), p.get("name"),
                mt.REGION_LOCATION_NAMES, "Town Map location", field="town_map.location")
            add("town_map.csv", "point.%s" % _slug(p.get("point_name") or ""), p.get("point_name"),
                mt.REGION_LOCATION_DESCRIPTIONS, "Town Map point of interest", field="town_map.point")
    for e in entries("phone"):
        cid = _slug(str(e["id"]))
        for kind in ("intro", "intro_morning", "intro_afternoon", "intro_evening", "body", "body1", "body2",
                     "battle_request", "battle_remind", "end"):
            for n, msg in enumerate(e.get(kind) or []):
                add("phone.csv", "%s.%s.%d" % (cid, kind, n + 1), msg, mt.PHONE_MESSAGES,
                    "Phone call (%s); \\m starts a new message" % kind, message=True)
    for e in entries("metadata"):
        add("metadata.csv", "storage_creator", e.get("real_storage_creator"), mt.STORAGE_CREATOR_NAME,
            "Name of the PC storage creator", field="metadata.storage_creator")
    for name, d in sorted(data.items()):
        if d.subdir != "battle_facility" or not name.endswith("_trainers"):
            continue
        for e in d.entries():
            for field, mtype, what, msg in (("name", mt.TRAINER_NAMES, "Battle Frontier trainer name", False),
                                            ("begin_speech", mt.FRONTIER_INTRO_SPEECHES, "Frontier intro", True),
                                            ("end_speech_win", mt.FRONTIER_END_SPEECHES_WIN, "Frontier win", True),
                                            ("end_speech_lose", mt.FRONTIER_END_SPEECHES_LOSE, "Frontier loss", True)):
                text = e.get(field)
                if isinstance(text, str) and text:
                    add("battle_facility.csv", "%s.%s" % (field, short_hash(text)), text, mtype, what,
                        message=msg, field=("trainers.name" if field == "name" else None))
    return out


#===============================================================================
# Scripts
#===============================================================================
_INTL_RE = re.compile(r'(?:_INTL|_ISPRINTF)\s*\(\s*"((?:[^\\"]*\\"?)*[^"]*)"')


def _unescape_script(s):
    """The unescaping of Translator.find_translatable_text_from_RGSS_script."""
    s = s.replace("\\r", "\r").replace("\\n", "\n").replace("\\1", "\x01")
    s = s.replace('\\"', '"').replace("\\\\", "\\")
    return s


def script_strings(dirs=None):
    """_INTL/_ISPRINTF literals in the game scripts. @return list of SourceString"""
    dirs = cfg.SCRIPT_DIRS if dirs is None else dirs
    out = []
    for base in dirs:
        if not os.path.isdir(base):
            continue
        for folder, subdirs, files in os.walk(base):
            subdirs.sort()
            for name in sorted(files):
                if not name.endswith(".rb"):
                    continue
                path = os.path.join(folder, name)
                with open(path, "r", encoding="utf-8", errors="replace") as f:
                    code = f.read()
                rel = os.path.relpath(path, cfg.ROOT).replace(os.sep, "/")
                for m in _INTL_RE.finditer(code):
                    text = _unescape_script(m.group(1))
                    if text == "":
                        continue
                    line = code.count("\n", 0, m.start()) + 1
                    out.append(SourceString("scripts.csv", "s." + short_hash(text), text, mt.SCRIPT_TEXTS,
                                            context="%s:%d" % (rel, line)))
    return out


#===============================================================================
# Events
#===============================================================================
def event_data_dir(data_dir=None):
    """Where to read event text from. @return (folder, compiled) or (None, False)

    The source maps in src/assets/data are read, and extract_events.rb replays
    the compiler's Show Text fixes, which gives exactly the text of the
    compiled maps in build/Data. When the maps are made in Tiled (src/tiled
    has a map registry), the maps `make tiled` compiled into build/Data are
    read instead (they haven't been through the game's compiler either).
    """
    if not data_dir and os.path.isfile(os.path.join(cfg.ROOT, "src", "tiled", "maps", "registry.json")):
        data_dir = os.path.join(cfg.ROOT, "build", "Data")
    data_dir = data_dir or cfg.DATA_DIR
    if os.path.isfile(os.path.join(data_dir, "MapInfos.rxdata")):
        return data_dir, False
    return None, False


def event_strings(data_dir, compiled=False, ruby="ruby"):
    """Text of the maps and common events in data_dir. @return list of SourceString"""
    args = [ruby, cfg.EXTRACT_EVENTS, data_dir] + (["--compiled"] if compiled else [])
    proc = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        raise RuntimeError("extract_events.rb failed:\n" + proc.stderr.decode("utf-8", "replace"))
    doc = json.loads(proc.stdout.decode("utf-8"))
    maps = {int(k): v for k, v in doc["maps"].items()}
    out = []
    for t in doc["texts"]:
        map_id = t["map"]
        if map_id == 0:
            file = "events/common_events.csv"
            key = "ce%03d.c%03d" % (t["event"], t["command"])
            where = "Common event %d" % t["event"]
        else:
            file = "events/map%03d.csv" % map_id
            key = "ev%03d.p%d.c%03d" % (t["event"], t["page"] + 1, t["command"])
            where = "Map %d (%s), event %d, page %d" % (map_id, maps.get(map_id, ""), t["event"], t["page"] + 1)
        if t["choice"] is not None:
            key += ".%s%d" % ("choice" if t["kind"] == "choice" else "script", t["choice"] + 1)
        kind = {"text": "Show Text", "choice": "Show Choices option", "script": "_I() text in a script"}[t["kind"]]
        out.append(SourceString(file, key, t["text"], mt.EVENT_TEXTS, map_id=map_id,
                                context="%s: %s" % (where, kind), message=(t["kind"] == "text"),
                                field=("events.choice" if t["kind"] == "choice" else None)))
    return out


#===============================================================================
# All
#===============================================================================
def merge_duplicates(strings):
    """Keeps one string per file and runtime key; the others go to .also.

    The engine finds a translation by its English text, so two strings with the
    same English in the same table can only have one translation anyway.
    """
    seen = {}
    out = []
    for s in strings:
        k = (s.file,) + s.runtime_key
        first = seen.get(k)
        if first is None:
            seen[k] = s
            out.append(s)
        else:
            first.also.append(s.key)
    keys = {}
    for s in out:
        if (s.file, s.key) in keys:   # same key, different English (e.g. slug clash)
            n = 2
            while (s.file, "%s~%d" % (s.key, n)) in keys:
                n += 1
            s.key = "%s~%d" % (s.key, n)
        keys[(s.file, s.key)] = s
    return out


def strings_from_event_csvs(lang_dir):
    """Event strings rebuilt from a language's event CSVs (their english column).

    Used when the map data isn't installed, so translations of event text can
    still be checked and built. @return list of SourceString
    """
    from .csvio import OBSOLETE, CsvError, read_csv
    out = []
    folder = os.path.join(lang_dir, "events")
    if not os.path.isdir(folder):
        return out
    for name in sorted(os.listdir(folder)):
        m = re.match(r"^(?:map(\d+)|(common_events))\.csv$", name, re.I)
        if not m:
            continue
        map_id = int(m.group(1)) if m.group(1) else 0
        try:
            _, rows = read_csv(os.path.join(folder, name))
        except CsvError:
            continue
        for row in rows:
            if row.get_value("status") == OBSOLETE or not row.get_value("key"):
                continue
            key = row.get_value("key")
            out.append(SourceString("events/" + name, key, row.get_value("english"), mt.EVENT_TEXTS,
                                    map_id=map_id, context=row.get_value("context"),
                                    message=(".choice" not in key and ".script" not in key),
                                    field=("events.choice" if ".choice" in key else None)))
    return out


def gather(pbs_dir=cfg.PBS_DIR, script_dirs=None, data_dir=None, events=True, log=print):
    """Every translatable string of the game.

    @return (list of SourceString, True if event text was read from map data)
    """
    strings = pbs_strings(pbs_dir) + script_strings(script_dirs)
    loaded = False
    if events:
        folder, compiled = event_data_dir(data_dir)
        if folder:
            strings += event_strings(folder, compiled)
            loaded = True
            log("Read event text from %s%s." % (os.path.relpath(folder, cfg.ROOT),
                                                " (compiled)" if compiled else ""))
        else:
            log("No map data in src/assets/data (run tools/scripts/install_assets.sh); event text is taken "
                "from the event CSVs as they are.")
    return merge_duplicates(strings), loaded
