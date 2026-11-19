"""@package pbsjson.datasets
One handler per kind of PBS file. Each handler reads a PBS file into a list of
JSON entries, writes entries back as PBS text, and names and validates them.

Most files are read straight from their engine schema (GenericDataset). The
rest have their own formats, mirroring the compiler (Compiler.compile_*) and
the engine's PBS writer (Compiler.write_*):
- encounters.txt (EncounterDataset)
- trainers.txt (TrainerDataset)
- map_connections.txt (ConnectionDataset)
- regional_dexes.txt (RegionalDexDataset)
- battle_facility_lists.txt and the files it names (BattleFacility*Dataset)
"""

import re
import unicodedata

from .fields import FieldGroup
from .pbs_text import (EOL, HEADER, SEPARATOR, PbsError, cast_value,
                       is_comment_or_blank, prepline, split_csv_line, write_record)

_SECTION_RE = re.compile(r"^\s*\[\s*(.*)\s*\]\s*$")
_SECTION_PLUS_RE = re.compile(r"^\s*\[\s*(.+)\s*\]\s*$")
_PROPERTY_RE = re.compile(r"^\s*(\w+)\s*=\s*(.*)$")
_NUMBER_RE = re.compile(r"^\d+$")


def slug(text):
    """A snake_case file name stem for an id (e.g. "LEADER_Brock,Brock")."""
    text = unicodedata.normalize("NFKD", str(text)).encode("ascii", "ignore").decode("ascii")
    text = re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")
    return text or "entry"


def join_pbs(lines):
    """Joins PBS lines with the engine's line ending."""
    return EOL.join(lines) + EOL


def read_sections(lines, path, is_multi_line, numbered=False):
    """Port of Compiler.pbEachFileSectionEx/pbEachFileSection.

    @param lines (line number, text) pairs from pbs_text.read_lines
    @param path file name for error messages
    @param is_multi_line function(PBS key) -> True for "^" keys
    @param numbered True to keep only sections named by a number
    @return list of (line number, section name, {key: text or [texts]})
    """
    sections = []
    current = None
    for lineno, line in lines:
        if is_comment_or_blank(line):
            continue
        line = prepline(line)
        if line == "":
            continue
        match = _SECTION_RE.match(line)
        if match:
            current = (lineno, match.group(1).rstrip(), {})
            sections.append(current)
            continue
        if current is None:
            raise PbsError("Expected a section at the beginning of the file.", path, lineno)
        match = _PROPERTY_RE.match(line)
        if not match:
            raise PbsError("Bad line syntax (expected syntax like XXX=YYY).", path, lineno)
        key, value = match.group(1), match.group(2).rstrip()
        if is_multi_line(key):
            current[2].setdefault(key, []).append(value)
        else:
            current[2][key] = value
    if numbered:
        return [s for s in sections if _NUMBER_RE.match(s[1])]
    return [s for s in sections if s[1] != ""]


def prepped_lines(lines):
    """Port of Compiler.pbCompilerEachPreppedLine: (line number, prepped text)."""
    for lineno, line in lines:
        if is_comment_or_blank(line):
            continue
        line = prepline(line)
        if line == "" or line.startswith("#"):
            continue
        yield lineno, line


def _warn_at(warn, path, lineno):
    return lambda message: warn("%s:%d: %s" % (path, lineno, message))


class Dataset:
    """Base class for a kind of PBS file."""

    ## The PBS base filename (and JSON name), e.g. "pokemon".
    name = None
    ## True if each entry gets its own JSON file.
    split = False

    def parse_file(self, lines, path, warn):
        """Reads a PBS file into JSON entries."""
        raise NotImplementedError

    def write_file(self, entries):
        """Writes JSON entries as the text of a PBS file (without BOM)."""
        raise NotImplementedError

    def entry_key(self, entry):
        """The text that identifies an entry (its section name in PBS)."""
        raise NotImplementedError

    def entry_stem(self, entry):
        """The JSON file name stem for an entry of a split dataset."""
        return slug(self.entry_key(entry))

    def entry_schema(self, schema_gen):
        """The JSON Schema of one entry."""
        return {"type": "object"}

    def validate_entry(self, entry, check):
        """Checks one entry; check is a validate.EntryChecker."""

    def validate_all(self, entries, check):
        """Checks things that involve several entries of this dataset."""


class GenericDataset(Dataset):
    """A section-based PBS file read from its engine schema."""

    def __init__(self, config, name, schema_entries, split=False, numbered=False,
                 header_format=None, schema_for=None, stem_prefix=""):
        self.config = config
        self.name = name
        self.split = split
        ## True if only sections named with a number are compiled.
        self.numbered = numbered
        ## Optional function(entry) -> section name text, overriding the schema.
        self.header_format = header_format
        ## Text put before entry file names (e.g. "map_").
        self.stem_prefix = stem_prefix
        ## The main field group.
        self.group = FieldGroup(schema_entries, name, config.names)
        ## Optional function(section JSON) -> FieldGroup, for files with two
        ## kinds of section (metadata.txt).
        self.schema_for = schema_for or (lambda entry: self.group)

    def all_groups(self):
        """Every field group this dataset uses."""
        return [self.group]

    def _is_multi_line(self, key):
        return any(group.is_multi_line(key) for group in self.all_groups())

    def parse_file(self, lines, path, warn):
        entries = []
        for lineno, section_name, contents in read_sections(lines, path, self._is_multi_line,
                                                             self.numbered):
            try:
                entry = self.group.section_to_json(section_name)
                group = self.schema_for(entry)
                if group is not self.group:
                    entry = group.section_to_json(section_name)
                entry.update(group.properties_to_json(contents, _warn_at(warn, path, lineno)))
                self.after_parse(entry)
            except PbsError as e:
                raise PbsError("[%s] %s" % (section_name, e.message), path, lineno)
            entries.append(entry)
        return entries

    def after_parse(self, entry):
        """Hook to tidy an entry after it is read."""

    def write_file(self, entries):
        out = [HEADER]
        for entry in entries:
            group = self.schema_for(entry)
            out.append(SEPARATOR)
            if self.header_format:
                out.append("[%s]" % self.header_format(entry))
            else:
                out.append("[%s]" % group.section_from_json(entry))
            out.extend(group.properties_to_lines(entry))
        return join_pbs(out)

    def entry_key(self, entry):
        if self.header_format:
            return self.header_format(entry)
        return self.schema_for(entry).section_from_json(entry)

    def entry_stem(self, entry):
        return self.stem_prefix + slug(self.entry_key(entry))

    def entry_schema(self, schema_gen):
        return schema_gen.groups_schema(self.name, self.all_groups())

    def validate_entry(self, entry, check):
        group = self.schema_for(entry)
        check.group(self.name, group, entry)


class SpeciesDataset(GenericDataset):
    """pokemon.txt and pokemon_forms.txt.

    Evolution parameters are text in the schema ("s"/"S"); they are stored as
    integers in JSON when the evolution method takes an integer.
    """

    def after_parse(self, entry):
        params = self.config.extra.get("evolution_parameters", {})
        for evo in entry.get("evolutions", []):
            value = evo.get("parameter")
            if value == "":
                # "Evolutions" (one line) reads a missing parameter as "",
                # "Evolution" (one per line) as nothing; both mean none.
                del evo["parameter"]
                continue
            if isinstance(value, str) and params.get(evo.get("method")) == "Integer" \
                    and re.match(r"^-?\d+$", value):
                evo["parameter"] = int(value)

    def validate_entry(self, entry, check):
        # Integer parameters are checked below; the schema itself says "s".
        plain = dict(entry)
        if isinstance(entry.get("evolutions"), list):
            plain["evolutions"] = [dict(e, parameter=str(e["parameter"]))
                                   if isinstance(e, dict) and isinstance(e.get("parameter"), int) else e
                                   for e in entry["evolutions"]]
        super().validate_entry(plain, check)
        params = self.config.extra.get("evolution_parameters", {})
        for i, evo in enumerate(entry.get("evolutions", []) or []):
            if not isinstance(evo, dict):
                continue
            where = "evolutions[%d]" % i
            check.reference("Species", evo.get("species"), where + ".species")
            method = evo.get("method")
            if method not in params:
                continue
            param_type = params[method]
            value = evo.get("parameter")
            if param_type is None:
                if value not in (None, ""):
                    check.error(where + ".parameter", "evolution method %s takes no parameter" % method)
            elif value is None:
                check.error(where + ".parameter", "evolution method %s needs a parameter" % method)
            elif param_type == "Integer":
                if not isinstance(value, int) or isinstance(value, bool):
                    check.error(where + ".parameter", "evolution method %s needs an integer" % method)
            elif param_type != "String":
                check.reference(param_type, value, where + ".parameter")


class MetadataDataset(GenericDataset):
    """metadata.txt: section 0 is global metadata, the others are players."""

    def __init__(self, config, name, split=False):
        classes = config.classes
        super().__init__(config, name, classes["Metadata"]["schema"], split=split, numbered=True)
        self.player_group = FieldGroup(classes["PlayerMetadata"]["schema"], name, config.names)
        self.schema_for = lambda entry: self.group if entry.get("id") == 0 else self.player_group

    def all_groups(self):
        return [self.group, self.player_group]

    def validate_all(self, entries, check):
        ids = [e.get("id") for e in entries]
        if 0 not in ids:
            check.error("", "global metadata (section 0) is not defined")
        elif "home" not in entries[ids.index(0)]:
            check.error("", "the entry 'Home' is required in metadata section 0")
        if 1 not in ids:
            check.error("", "metadata for player character 1 (section 1) is not defined")


class TrainerDataset(Dataset):
    """trainers.txt: trainers with indented properties for each Pokémon."""

    def __init__(self, config, name, split=False):
        self.config = config
        self.name = name
        self.split = split
        info = config.classes["Trainer"]
        self.group = FieldGroup(info["schema"], name, config.names)
        self.sub_group = FieldGroup(info["sub_schema"], name, config.names)
        self.pokemon_field = self.group.by_key["Pokemon"]

    def parse_file(self, lines, path, warn):
        entries = []
        entry = None
        pokemon = None
        for lineno, line in prepped_lines(lines):
            try:
                match = _SECTION_PLUS_RE.match(line)
                if match:
                    entry = self.group.section_to_json(match.group(1))
                    entries.append(entry)
                    pokemon = None
                    continue
                match = _PROPERTY_RE.match(line)
                if not match:
                    continue
                if entry is None:
                    raise PbsError("Expected a section at the beginning of the file.")
                key, value = match.group(1), match.group(2).rstrip()
                field = self.group.field_for_key(key)
                if field is not None and field.key != "SectionName":
                    if field.key == "Pokemon":
                        pokemon = field.parse(value)
                        entry.setdefault("pokemon", []).append(pokemon)
                    else:
                        entry[field.json_key] = field.parse(value)
                    continue
                field = self.sub_group.field_for_key(key)
                if field is not None:
                    if pokemon is None:
                        raise PbsError("Pokémon hasn't been defined yet!")
                    pokemon[field.json_key] = field.parse(value)
                    continue
                warn("%s:%d: Unknown property %s (ignored, as the compiler does)." % (path, lineno, key))
            except PbsError as e:
                raise PbsError(e.message, path, lineno)
        for entry in entries:
            self._order(entry)
        return entries

    def _order(self, entry):
        """Puts an entry's keys and its Pokémon's keys in schema order."""
        ordered = {k: entry[k] for k in self.group.section_keys() if k in entry}
        for key, _ in self.group.property_fields():
            if key in entry:
                ordered[key] = entry[key]
        entry.clear()
        entry.update(ordered)
        for i, pkmn in enumerate(entry.get("pokemon", [])):
            new = {k: pkmn[k] for k in self.pokemon_field.names if k in pkmn}
            for key, _ in self.sub_group.property_fields():
                if key in pkmn:
                    new[key] = pkmn[key]
            entry["pokemon"][i] = new

    def write_file(self, entries):
        out = [HEADER]
        for entry in entries:
            out.append(SEPARATOR)
            out.append("[%s]" % self.group.section_from_json(entry))
            for key, field in self.group.property_fields():
                if field.key == "Pokemon":
                    continue
                out.extend(field.format_lines(entry.get(key)))
            for pkmn in entry.get("pokemon", []):
                out.append("Pokemon = %s" % self.pokemon_field.format_one(pkmn))
                for key, field in self.sub_group.property_fields():
                    out.extend("    " + line for line in field.format_lines(pkmn.get(key)))
        return join_pbs(out)

    def entry_key(self, entry):
        return self.group.section_from_json(entry)

    def entry_schema(self, schema_gen):
        schema = schema_gen.groups_schema(self.name, [self.group], skip=["pokemon"])
        pkmn = schema_gen.groups_schema(self.name, [self.sub_group])
        names = self.pokemon_field.names
        for name, letter, enum in zip(names, self.pokemon_field.letters, self.pokemon_field.enums):
            pkmn["properties"][name] = schema_gen.letter_schema(letter, enum)
        pkmn["required"] = list(names)
        schema["properties"]["pokemon"] = {"type": "array", "items": pkmn}
        return schema

    def validate_entry(self, entry, check):
        check.group(self.name, self.group, entry, skip=["pokemon"])
        pokemon = entry.get("pokemon", [])
        if not isinstance(pokemon, list):
            check.error("pokemon", "must be a list")
            return
        if len(pokemon) == 0:
            check.error("pokemon", "a trainer needs at least one Pokémon")
        max_level = self.config.extra.get("max_level")
        for i, pkmn in enumerate(pokemon):
            where = "pokemon[%d]" % i
            if not isinstance(pkmn, dict):
                check.error(where, "must be an object")
                continue
            check.record(self.name, self.pokemon_field, {k: pkmn.get(k) for k in self.pokemon_field.names},
                         where)
            if max_level and isinstance(pkmn.get("level"), int) and pkmn["level"] > max_level:
                check.error(where + ".level", "level %d is above the maximum of %d" % (pkmn["level"], max_level))
            check.group(self.name, self.sub_group, pkmn, where=where, skip=list(self.pokemon_field.names))


class EncounterDataset(Dataset):
    """encounters.txt: [map,version] sections of encounter types and slots."""

    def __init__(self, config, name, split=False):
        self.config = config
        self.name = name
        self.split = split

    def parse_file(self, lines, path, warn):
        entries = []
        entry = None
        current = None
        for lineno, line in prepped_lines(lines):
            try:
                if current is not None and re.match(r"^\d+,", line):
                    values = split_csv_line(line)
                    if len(values) < 3:
                        raise PbsError("Expected a species entry line for encounter type %s."
                                       % current["type"])
                    slot = {
                        "chance": cast_value(values[0], "v"),
                        "species": cast_value(values[1], "e"),
                        "min_level": cast_value(values[2], "v"),
                    }
                    if len(values) > 3 and values[3] != "":
                        slot["max_level"] = cast_value(values[3], "v")
                    current["slots"].append(slot)
                    continue
                match = re.match(r"^\[\s*(.+)\s*\]$", line)
                if match:
                    parts = [p.strip() for p in match.group(1).split(",")]
                    entry = {"map": _ruby_to_i(parts[0])}
                    if len(parts) > 1 and _ruby_to_i(parts[1]) != 0:
                        entry["version"] = _ruby_to_i(parts[1])
                    entry["types"] = []
                    entries.append(entry)
                    current = None
                    continue
                if entry is None:
                    raise PbsError('Expected a map number, got "%s" instead.' % line)
                values = [v.strip() for v in line.split(",")]
                current = {"type": values[0]}
                if len(values) > 1 and values[1] != "":
                    current["step_chance"] = _ruby_to_i(values[1])
                current["slots"] = []
                entry["types"].append(current)
            except PbsError as e:
                raise PbsError(e.message, path, lineno)
        return entries

    def write_file(self, entries):
        out = [HEADER]
        for entry in entries:
            out.append(SEPARATOR)
            if entry.get("version", 0):
                out.append("[%03d,%d]" % (entry["map"], entry["version"]))
            else:
                out.append("[%03d]" % entry["map"])
            for enc in entry.get("types", []):
                if not enc.get("slots"):
                    continue
                if enc.get("step_chance"):
                    out.append("%s,%d" % (enc["type"], enc["step_chance"]))
                else:
                    out.append(enc["type"])
                for slot in enc["slots"]:
                    max_level = slot.get("max_level", slot["min_level"])
                    if max_level == slot["min_level"]:
                        out.append("    %d,%s,%d" % (slot["chance"], slot["species"], slot["min_level"]))
                    else:
                        out.append("    %d,%s,%d,%d" % (slot["chance"], slot["species"],
                                                        slot["min_level"], max_level))
        return join_pbs(out)

    def entry_key(self, entry):
        if entry.get("version", 0):
            return "%03d,%d" % (entry.get("map", 0), entry["version"])
        return "%03d" % entry.get("map", 0)

    def entry_stem(self, entry):
        return "map_" + slug(self.entry_key(entry))

    def entry_schema(self, schema_gen):
        types = list(self.config.extra.get("encounter_types", {}).keys())
        slot = {
            "type": "object",
            "properties": {
                "chance": {"type": "integer", "minimum": 1},
                "species": {"type": "string", "description": "A species id from pokemon.txt."},
                "min_level": {"type": "integer", "minimum": 1},
                "max_level": {"type": "integer", "minimum": 1},
            },
            "required": ["chance", "species", "min_level"],
            "additionalProperties": False,
        }
        enc_type = {
            "type": "object",
            "properties": {
                "type": {"type": "string", "enum": types} if types else {"type": "string"},
                "step_chance": {"type": "integer", "minimum": 0},
                "slots": {"type": "array", "items": slot},
            },
            "required": ["type", "slots"],
            "additionalProperties": False,
        }
        return {
            "type": "object",
            "properties": {
                "$schema": {"type": "string"},
                "map": {"type": "integer", "minimum": 0, "description": "Map ID."},
                "version": {"type": "integer", "minimum": 0},
                "types": {"type": "array", "items": enc_type},
            },
            "required": ["map", "types"],
            "additionalProperties": False,
        }

    def validate_entry(self, entry, check):
        check.keys(entry, {"map", "version", "types"}, "")
        check.scalar(entry.get("map"), "u", None, "map")
        if "version" in entry:
            check.scalar(entry["version"], "u", None, "version")
        types = self.config.extra.get("encounter_types", {})
        max_level = self.config.extra.get("max_level")
        seen = set()
        for i, enc in enumerate(entry.get("types") or []):
            where = "types[%d]" % i
            if not isinstance(enc, dict):
                check.error(where, "must be an object")
                continue
            check.keys(enc, {"type", "step_chance", "slots"}, where)
            if types and enc.get("type") not in types:
                check.error(where + ".type", "undefined encounter type %r" % enc.get("type"))
            if enc.get("type") in seen:
                check.error(where + ".type", "encounter type %s is listed twice" % enc.get("type"))
            seen.add(enc.get("type"))
            if "step_chance" in enc:
                check.scalar(enc["step_chance"], "u", None, where + ".step_chance")
            for j, slot in enumerate(enc.get("slots") or []):
                swhere = "%s.slots[%d]" % (where, j)
                if not isinstance(slot, dict):
                    check.error(swhere, "must be an object")
                    continue
                check.keys(slot, {"chance", "species", "min_level", "max_level"}, swhere)
                check.scalar(slot.get("chance"), "v", None, swhere + ".chance")
                check.reference("Species", slot.get("species"), swhere + ".species")
                check.scalar(slot.get("min_level"), "v", None, swhere + ".min_level")
                if "max_level" in slot:
                    check.scalar(slot["max_level"], "v", None, swhere + ".max_level")
                lo, hi = slot.get("min_level"), slot.get("max_level", slot.get("min_level"))
                if isinstance(lo, int) and isinstance(hi, int):
                    if lo > hi:
                        check.error(swhere, "minimum level is greater than maximum level")
                    if max_level and hi > max_level:
                        check.error(swhere, "level %d is above the maximum of %d" % (hi, max_level))


def _ruby_to_i(text):
    """Ruby's String#to_i: the leading integer of a string, or 0."""
    match = re.match(r"^\s*([-+]?\d+)", text or "")
    return int(match.group(1)) if match else 0


class ConnectionDataset(Dataset):
    """map_connections.txt: one connection per line."""

    SIDES = {"N": "N", "North": "N", "E": "E", "East": "E",
             "S": "S", "South": "S", "W": "W", "West": "W"}
    OPPOSITE = {"N": "S", "S": "N", "E": "W", "W": "E"}
    KEYS = ["map", "side", "offset", "other_map", "other_side", "other_offset"]

    def __init__(self, config, name):
        self.config = config
        self.name = name

    def parse_file(self, lines, path, warn):
        entries = []
        for lineno, line in prepped_lines(lines):
            values = split_csv_line(line)
            try:
                rec = [cast_value(values[i] if i < len(values) else None, letter)
                       for i, letter in enumerate("iyiiyi")]
            except PbsError as e:
                raise PbsError(e.message, path, lineno)
            entries.append(dict(zip(self.KEYS, rec)))
        return entries

    def write_file(self, entries):
        out = [HEADER, SEPARATOR]
        for e in entries:
            out.append(",".join(str(e.get(k)) for k in self.KEYS))
        return join_pbs(out)

    def entry_key(self, entry):
        return ",".join(str(entry.get(k)) for k in self.KEYS)

    def entry_schema(self, schema_gen):
        side = {"oneOf": [{"type": "string", "enum": list(self.SIDES)}, {"type": "integer"}],
                "description": "Edge of the map (N, E, S, W), or an x coordinate."}
        return {
            "type": "object",
            "properties": {
                "map": {"type": "integer"}, "side": side, "offset": {"type": "integer"},
                "other_map": {"type": "integer"}, "other_side": side, "other_offset": {"type": "integer"},
            },
            "required": list(self.KEYS),
            "additionalProperties": False,
        }

    def validate_entry(self, entry, check):
        check.keys(entry, set(self.KEYS), "")
        for key in ("map", "offset", "other_map", "other_offset"):
            check.scalar(entry.get(key), "i", None, key)
        sides = []
        for key in ("side", "other_side"):
            value = entry.get(key)
            if isinstance(value, str):
                if value not in self.SIDES:
                    check.error(key, "undefined side %r (expected one of %s)" % (value, ", ".join(self.SIDES)))
                sides.append(self.SIDES.get(value))
            elif not isinstance(value, int) or isinstance(value, bool):
                check.error(key, "must be a side (N, E, S, W) or an integer")
        if len(sides) == 2 and None not in sides and self.OPPOSITE[sides[0]] != sides[1]:
            check.error("other_side", "side %s of the first map must connect with side %s of the second map"
                        % (sides[0], self.OPPOSITE[sides[0]]))


class RegionalDexDataset(Dataset):
    """regional_dexes.txt: numbered sections listing species.

    Each line of species is kept as a list, so lines (usually one evolution
    family each) are written back as they were.
    """

    def __init__(self, config, name):
        self.config = config
        self.name = name

    def parse_file(self, lines, path, warn):
        entries = []
        entry = None
        for lineno, line in prepped_lines(lines):
            match = re.match(r"^\s*\[\s*(\d+)\s*\]\s*$", line)
            if match:
                entry = {"id": int(match.group(1)), "families": []}
                entries.append(entry)
                continue
            if entry is None:
                raise PbsError("Expected a section at the beginning of the file.", path, lineno)
            row = [s.strip() for s in line.split(",") if s.strip() != ""]
            if row:
                entry["families"].append(row)
        return entries

    def write_file(self, entries):
        out = [HEADER]
        for entry in entries:
            out.append(SEPARATOR)
            out.append("[%d]" % entry["id"])
            for row in entry.get("families", []):
                out.append(",".join(row))
        return join_pbs(out)

    def entry_key(self, entry):
        return str(entry.get("id"))

    def entry_schema(self, schema_gen):
        return {
            "type": "object",
            "properties": {
                "id": {"type": "integer", "minimum": 0},
                "families": {
                    "type": "array",
                    "description": "Lines of species ids from pokemon.txt, in Dex order.",
                    "items": {"type": "array", "items": {"type": "string"}},
                },
            },
            "required": ["id", "families"],
            "additionalProperties": False,
        }

    def validate_entry(self, entry, check):
        check.keys(entry, {"id", "families"}, "")
        check.scalar(entry.get("id"), "u", None, "id")
        seen = set()
        for i, row in enumerate(entry.get("families") or []):
            if not isinstance(row, list):
                check.error("families[%d]" % i, "must be a list of species")
                continue
            for j, species in enumerate(row):
                where = "families[%d][%d]" % (i, j)
                check.reference("Species", species, where)
                if species in seen:
                    check.error(where, "species %s is listed twice" % species)
                seen.add(species)


class BattleFacilityListDataset(Dataset):
    """battle_facility_lists.txt: the trainer and Pokémon files of each list."""

    def __init__(self, config, name):
        self.config = config
        self.name = name

    def parse_file(self, lines, path, warn):
        entries = []
        for lineno, name, contents in read_sections(lines, path, lambda key: False):
            if name not in ("DefaultTrainerList", "TrainerList"):
                warn("%s:%d: Section [%s] is ignored by the compiler." % (path, lineno, name))
                continue
            entry = {"default": name == "DefaultTrainerList"}
            for key, value in contents.items():
                if key == "Trainers":
                    entry["trainers"] = csv_unquote_s(value)
                elif key == "Pokemon":
                    entry["pokemon"] = csv_unquote_s(value)
                elif key == "Challenges":
                    entry["challenges"] = [v for v in split_csv_line(value) if v != ""]
                else:
                    warn("%s:%d: Unknown property %s (ignored)." % (path, lineno, key))
            entries.append({k: entry[k] for k in ("default", "trainers", "pokemon", "challenges")
                            if k in entry})
        return entries

    def write_file(self, entries):
        out = [HEADER]
        for entry in entries:
            out.append(SEPARATOR)
            out.append("[DefaultTrainerList]" if entry.get("default") else "[TrainerList]")
            out.append("Trainers = " + entry.get("trainers", ""))
            out.append("Pokemon = " + entry.get("pokemon", ""))
            if not entry.get("default"):
                out.append("Challenges = " + ",".join(entry.get("challenges", [])))
        return join_pbs(out)

    def entry_key(self, entry):
        return "%s,%s" % (entry.get("trainers"), entry.get("pokemon"))

    def referenced_files(self, entries):
        """The trainer and Pokémon PBS file names the lists refer to."""
        trainers, pokemon = [], []
        for entry in entries:
            if entry.get("trainers") and entry["trainers"] not in trainers:
                trainers.append(entry["trainers"])
            if entry.get("pokemon") and entry["pokemon"] not in pokemon:
                pokemon.append(entry["pokemon"])
        return trainers, pokemon

    def entry_schema(self, schema_gen):
        return {
            "type": "object",
            "properties": {
                "default": {"type": "boolean", "description": "True for [DefaultTrainerList]."},
                "trainers": {"type": "string", "description": "Trainers PBS file, e.g. battle_tower_trainers.txt."},
                "pokemon": {"type": "string", "description": "Pokémon PBS file, e.g. battle_tower_pokemon.txt."},
                "challenges": {"type": "array", "items": {"type": "string"}},
            },
            "required": ["default", "trainers", "pokemon"],
            "additionalProperties": False,
        }

    def validate_entry(self, entry, check):
        check.keys(entry, {"default", "trainers", "pokemon", "challenges"}, "")
        if not isinstance(entry.get("default"), bool):
            check.error("default", "must be true or false")
        for key in ("trainers", "pokemon"):
            value = entry.get(key)
            if not isinstance(value, str) or not value:
                check.error(key, "a file name is required")
            elif not check.has_battle_facility_file(value):
                check.error(key, "%s is not in src/pbs/battle_facility/" % value)


def csv_unquote_s(value):
    """Reads an "s" value (used where the compiler uses an "s" schema)."""
    return cast_value(split_csv_line(value)[0] if split_csv_line(value) else "", "s")


class BattleFacilityTrainersDataset(Dataset):
    """A Battle Tower/Cup trainers file named by battle_facility_lists.txt."""

    KEYS = [("Type", "type", "e"), ("Name", "name", "s"), ("BeginSpeech", "begin_speech", "s"),
            ("EndSpeechWin", "end_speech_win", "s"), ("EndSpeechLose", "end_speech_lose", "s"),
            ("PokemonNos", "pokemon_nos", "*u")]

    def __init__(self, config, name):
        self.config = config
        self.name = name

    def parse_file(self, lines, path, warn):
        entries = []
        by_key = {k: (j, t) for k, j, t in self.KEYS}
        for lineno, _, contents in read_sections(lines, path, lambda key: False):
            entry = {}
            for key, value in contents.items():
                if key not in by_key:
                    warn("%s:%d: Unknown property %s (ignored, as the compiler does)." % (path, lineno, key))
                    continue
                json_key, letters = by_key[key]
                try:
                    if letters == "*u":
                        entry[json_key] = [cast_value(v, "u") for v in split_csv_line(value) if v != ""]
                    else:
                        values = split_csv_line(value)
                        entry[json_key] = cast_value(values[0] if values else None, letters)
                except PbsError as e:
                    raise PbsError(e.message, path, lineno)
            entries.append({j: entry[j] for _, j, _ in self.KEYS if j in entry})
        return entries

    def write_file(self, entries):
        out = [HEADER]
        for i, entry in enumerate(entries):
            out.append(SEPARATOR)
            out.append("[%03d]" % i)
            for key, json_key, letters in self.KEYS:
                if json_key not in entry or entry[json_key] is None:
                    continue
                value = entry[json_key]
                if key == "Type":
                    text = str(value)
                elif key == "PokemonNos":
                    text = ",".join(str(v) for v in value)
                else:
                    text = write_record([value], letters)
                out.append("%s = %s" % (key, text))
        return join_pbs(out)

    def entry_key(self, entry):
        return "%s,%s" % (entry.get("type"), entry.get("name"))

    def entry_schema(self, schema_gen):
        return {
            "type": "object",
            "properties": {
                "type": {"type": "string", "description": "A trainer type id from trainer_types.txt."},
                "name": {"type": "string"},
                "begin_speech": {"type": "string"},
                "end_speech_win": {"type": "string"},
                "end_speech_lose": {"type": "string"},
                "pokemon_nos": {"type": "array", "items": {"type": "integer", "minimum": 0},
                                "description": "Line numbers (from 0) in the list's Pokémon file."},
            },
            "required": ["type", "name"],
            "additionalProperties": False,
        }

    def validate_entry(self, entry, check):
        check.keys(entry, {j for _, j, _ in self.KEYS}, "")
        check.reference("TrainerType", entry.get("type"), "type")
        for _, json_key, letters in self.KEYS[1:5]:
            if json_key in entry and not isinstance(entry[json_key], str):
                check.error(json_key, "must be text")
        for i, value in enumerate(entry.get("pokemon_nos") or []):
            check.scalar(value, "u", None, "pokemon_nos[%d]" % i)


class BattleFacilityPokemonDataset(Dataset):
    """A Battle Tower/Cup Pokémon file: SPECIES;ITEM;NATURE;EVS;MOVES lines."""

    EVS = ["HP", "ATK", "DEF", "SA", "SPATK", "SD", "SPDEF", "SPD"]

    def __init__(self, config, name):
        self.config = config
        self.name = name

    def parse_file(self, lines, path, warn):
        entries = []
        for lineno, line in lines:
            if is_comment_or_blank(line):
                continue
            pieces = re.split(r"\s*;\s*", line.strip())
            if len(pieces) < 5:
                raise PbsError("Expected SPECIES;ITEM;NATURE;EVS;MOVES.", path, lineno)
            entry = {"species": pieces[0]}
            if pieces[1]:
                entry["item"] = pieces[1]
            entry["nature"] = pieces[2]
            entry["evs"] = [v for v in re.split(r"\s*,\s*", pieces[3]) if v != ""]
            entry["moves"] = [v for v in re.split(r"\s*,\s*", pieces[4]) if v != ""]
            entries.append(entry)
        return entries

    def write_file(self, entries):
        out = [HEADER, SEPARATOR]
        for e in entries:
            moves = list(e.get("moves", []))
            while len(moves) < 4:
                moves.append("")
            out.append("%s;%s;%s;%s;%s" % (e.get("species", ""), e.get("item", ""), e.get("nature", ""),
                                           ",".join(e.get("evs", [])), ",".join(moves)))
        return join_pbs(out)

    def entry_key(self, entry):
        return ";".join(str(entry.get(k)) for k in ("species", "item", "nature"))

    def entry_schema(self, schema_gen):
        return {
            "type": "object",
            "properties": {
                "species": {"type": "string"},
                "item": {"type": "string"},
                "nature": schema_gen.enum_schema({"gamedata": "Nature"}),
                "evs": {"type": "array", "items": {"type": "string", "enum": self.EVS}},
                "moves": {"type": "array", "items": {"type": "string"}, "maxItems": 4},
            },
            "required": ["species", "nature", "evs", "moves"],
            "additionalProperties": False,
        }

    def validate_entry(self, entry, check):
        check.keys(entry, {"species", "item", "nature", "evs", "moves"}, "")
        # PBPokemon.fromInspected ignores ids it doesn't know.
        check.reference("Species", entry.get("species"), "species", tolerated=True)
        if "item" in entry:
            check.reference("Item", entry["item"], "item", tolerated=True)
        check.reference("Nature", entry.get("nature"), "nature", tolerated=True)
        for i, ev in enumerate(entry.get("evs") or []):
            if str(ev).upper() not in self.EVS:
                check.error("evs[%d]" % i, "undefined stat %r (expected one of %s)" % (ev, ", ".join(self.EVS)))
        moves = entry.get("moves") or []
        if len(moves) > 4:
            check.error("moves", "a Pokémon can know at most 4 moves")
        for i, move in enumerate(moves):
            check.reference("Move", move, "moves[%d]" % i, tolerated=True)


class RawDataset(Dataset):
    """A .txt file in the PBS folder that the compiler doesn't read (e.g. a
    Battle Tower list no battle_facility_lists.txt section names). It is kept
    as text in src/pbs/raw/ and copied back unchanged."""

    def __init__(self, config, name):
        self.config = config
        self.name = name

    def parse_file(self, lines, path, warn):
        with open(path, "rb") as f:
            return [f.read().decode("utf-8")]

    def write_file(self, entries):
        return entries[0] if entries else ""

    def entry_key(self, entry):
        return self.name


def build_datasets(config):
    """Creates the handler of every PBS file the engine compiles.

    @return dict of PBS base filename -> Dataset, in compile order
    """
    split = config.split
    classes = config.classes
    result = {}

    def add(dataset):
        result[dataset.name] = dataset

    for key, base in config.engine["pbs_files"].items():
        name = base
        if key == "Species":
            add(SpeciesDataset(config, name, classes["Species"]["schema"], split=name in split))
        elif key == "Species1":
            add(SpeciesDataset(config, name, classes["Species"]["form_schema"], split=name in split))
        elif key == "Encounter":
            add(EncounterDataset(config, name, split=name in split))
        elif key == "Trainer":
            add(TrainerDataset(config, name, split=name in split))
        elif key == "Metadata":
            add(MetadataDataset(config, name, split=name in split))
        elif key == "Connection":
            add(ConnectionDataset(config, name))
        elif key == "RegionalDex":
            add(RegionalDexDataset(config, name))
        elif key == "BattleFacility":
            add(BattleFacilityListDataset(config, name))
        else:
            info = classes.get(key)
            if not info or not info.get("schema"):
                raise PbsError("The engine schema has no SCHEMA for %s (%s.txt) and the converter has no "
                               "handler for it." % (key, base))
            header = None
            prefix = ""
            if key == "MapMetadata":
                # The engine writes map ids padded to 3 digits (write_map_metadata).
                header = lambda entry: "%03d" % entry.get("id", 0)
                prefix = "map_"
            add(GenericDataset(config, name, info["schema"], split=name in split, header_format=header,
                               stem_prefix=prefix))
    return result
