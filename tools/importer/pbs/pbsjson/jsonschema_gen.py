"""@package pbsjson.jsonschema_gen
Generates JSON Schemas (draft 2020-12) for the files in src/pbs, so editors
can check values and complete keys while you type. The converter's own
validator (validate.py) does the full checks, including ids across files.
"""

import os

from .datasets import BattleFacilityPokemonDataset, BattleFacilityTrainersDataset, build_datasets
from .store import SCHEMA_DIR, dumps, write_if_changed

DRAFT = "https://json-schema.org/draft/2020-12/schema"

_LETTER_DESCRIPTIONS = {
    "s": "Text.", "q": "Text (the rest of the line, written as is).",
    "n": "A name: letters, digits and underscores, not starting with a digit.",
    "m": "An id: letters, digits and underscores, not starting with a digit.",
    "x": "A hexadecimal number, as text.",
}


class SchemaGen:
    """Builds JSON Schemas from the engine schema dump."""

    def __init__(self, config):
        self.config = config

    def enum_schema(self, ref):
        """The schema for an enumeration reference."""
        if ref is None:
            return {"type": "string"}
        if "gamedata" in ref:
            name = ref["gamedata"]
            info = self.config.enums.get(name, {})
            if info.get("source") == "hardcoded" and info.get("values"):
                return {"type": "string", "enum": list(info["values"])}
            base = self.config.engine["pbs_files"].get(name)
            where = (" from %s.txt" % base) if base else ""
            return {"type": "string", "description": "A %s id%s." % (name, where)}
        if "array" in ref:
            return {"type": "string", "enum": list(ref["array"])}
        if "hash" in ref:
            return {"type": "string", "enum": list(ref["hash"].keys())}
        if "module" in ref:
            return {"type": "string", "enum": list(ref.get("values", {}).keys())}
        return {"type": "string"}

    def letter_schema(self, letter, enum):
        """The schema for one schema letter."""
        kind = letter.lower()
        if kind == "i":
            return {"type": "integer"}
        if kind == "u":
            return {"type": "integer", "minimum": 0}
        if kind == "v":
            return {"type": "integer", "minimum": 1}
        if kind == "f":
            return {"type": "number"}
        if kind == "b":
            return {"type": "boolean"}
        if kind == "e":
            return self.enum_schema(enum)
        if kind == "y":
            return {"anyOf": [{"type": "integer"}, self.enum_schema(enum)]}
        schema = {"type": "string"}
        if kind in ("n", "m"):
            schema["pattern"] = r"^(?![0-9])\w+$"
        if kind in ("s", "q"):
            schema["pattern"] = r"^[^#]*$"
        if kind in _LETTER_DESCRIPTIONS:
            schema["description"] = _LETTER_DESCRIPTIONS[kind]
        return schema

    def record_schema(self, field):
        """The schema for one record of a field."""
        if field.names is None:
            return self.letter_schema(field.letters[0], field.enums[0])
        props = {}
        required = []
        for name, letter, enum in zip(field.names, field.letters, field.enums):
            props[name] = self.letter_schema(letter, enum)
            if not letter.isupper():
                required.append(name)
        return {"type": "object", "properties": props, "required": required, "additionalProperties": False}

    def field_schema(self, field):
        """The schema for a property value."""
        schema = self.record_schema(field)
        if field.is_list:
            schema = {"type": "array", "items": schema}
        schema = dict(schema)
        schema.setdefault("description", "PBS key: %s" % field.key)
        return schema

    def groups_schema(self, dataset, groups, skip=()):
        """The schema of an entry described by one or more FieldGroups."""
        props = {"$schema": {"type": "string"}}
        required = None
        for group in groups:
            section = group.section_field
            group_required = []
            if section is not None and section.names:
                for name, letter, enum in zip(section.names, section.letters, section.enums):
                    props.setdefault(name, self.letter_schema(letter, enum))
                    if not letter.isupper():
                        group_required.append(name)
            elif section is not None:
                props.setdefault(section.json_key, self.letter_schema(section.letters[0], section.enums[0]))
                group_required.append(section.json_key)
            for key, field in group.property_fields():
                if key in skip:
                    continue
                props.setdefault(key, self.field_schema(field))
            required = group_required if required is None else [r for r in required if r in group_required]
        return {"type": "object", "properties": props, "required": required or [],
                "additionalProperties": False}


def index_schema():
    """The schema of a split dataset's _index.json."""
    return {
        "$schema": DRAFT,
        "title": "PBS dataset index",
        "description": "The order of the entries of each PBS file of a dataset. Entries are file "
                       "names (without .json) in this folder.",
        "type": "object",
        "properties": {
            "$schema": {"type": "string"},
            "files": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "suffix": {"type": "string", "description": "PBS file <name>_<suffix>.txt; empty for <name>.txt."},
                        "bom": {"type": "boolean", "description": "Write a UTF-8 BOM at the start of the file."},
                        "entries": {"type": "array", "items": {"type": "string"}},
                    },
                    "required": ["suffix", "entries"],
                    "additionalProperties": False,
                },
            },
        },
        "required": ["files"],
        "additionalProperties": False,
    }


def file_schema(title, entry):
    """The schema of a dataset kept in one JSON file."""
    return {
        "$schema": DRAFT,
        "title": title,
        "type": "object",
        "properties": {
            "$schema": {"type": "string"},
            "files": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "suffix": {"type": "string"},
                        "bom": {"type": "boolean"},
                        "entries": {"type": "array", "items": entry},
                    },
                    "required": ["suffix", "entries"],
                    "additionalProperties": False,
                },
            },
        },
        "required": ["files"],
        "additionalProperties": False,
    }


def write_schemas(config, src_dir):
    """Writes every JSON Schema into src/pbs/_schema. @return files written"""
    gen = SchemaGen(config)
    out_dir = os.path.join(src_dir, SCHEMA_DIR)
    written = 0
    docs = {"index.schema.json": index_schema()}
    for name, dataset in build_datasets(config).items():
        entry = dataset.entry_schema(gen)
        if dataset.split:
            doc = {"$schema": DRAFT, "title": "%s.txt entry" % name}
            doc.update(entry)
            docs["%s.entry.schema.json" % name] = doc
        else:
            entry = dict(entry)
            entry.get("properties", {}).pop("$schema", None)
            docs["%s.schema.json" % name] = file_schema("%s.txt" % name, entry)
    for cls, title in ((BattleFacilityTrainersDataset, "Battle facility trainers file"),
                       (BattleFacilityPokemonDataset, "Battle facility Pokémon file")):
        entry = cls(config, "").entry_schema(gen)
        key = "battle_facility_trainers" if cls is BattleFacilityTrainersDataset else "battle_facility_pokemon"
        docs["%s.schema.json" % key] = file_schema(title, entry)
    for filename, doc in docs.items():
        if write_if_changed(os.path.join(out_dir, filename), dumps(doc) + "\n"):
            written += 1
    return written
