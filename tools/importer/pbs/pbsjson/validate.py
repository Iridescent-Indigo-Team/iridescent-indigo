"""@package pbsjson.validate
Checks the JSON in src/pbs before it is exported: value types, enumerations
(using the values the engine dumped), ids that must exist in another PBS file,
duplicates and index consistency.
"""

import os
import re

from .datasets import BattleFacilityPokemonDataset, BattleFacilityTrainersDataset, RawDataset
from .store import BATTLE_FACILITY_DIR, orphan_files

_NAME_RE = re.compile(r"^(?![0-9])\w+$")
_HEX_RE = re.compile(r"^[A-F0-9]+$", re.IGNORECASE)


class Problem:
    """One validation error (or warning)."""

    def __init__(self, path, where, message, warning=False):
        ## The JSON file.
        self.path = path
        ## The field path inside the entry (e.g. "moves[2].level").
        self.where = where
        ## What is wrong.
        self.message = message
        ## True for problems the compiler tolerates; they don't stop an export.
        self.warning = warning

    def __str__(self):
        loc = self.path
        if self.where:
            loc += " (%s)" % self.where
        return "%s: %s" % (loc, self.message)


def _is_int(value):
    return isinstance(value, int) and not isinstance(value, bool)


class EntryChecker:
    """Checks the fields of one entry; collects problems."""

    def __init__(self, validator, path, prefix=""):
        self.validator = validator
        self.path = path
        self.prefix = prefix

    def _where(self, where):
        if self.prefix and where:
            return self.prefix + "." + where
        return self.prefix or where

    def error(self, where, message):
        """Records a problem at a field path."""
        self.validator.problems.append(Problem(self.path, self._where(where), message))

    def warning(self, where, message):
        """Records a problem the compiler tolerates."""
        self.validator.problems.append(Problem(self.path, self._where(where), message, warning=True))

    def keys(self, obj, allowed, where):
        """Reports keys of an object that aren't allowed."""
        for key in obj:
            if key not in allowed:
                self.error(where, "unknown key %r (expected one of: %s)" % (key, ", ".join(sorted(allowed))))

    def reference(self, gamedata, value, where, tolerated=False):
        """Checks that value is an id defined for a GameData class.

        @param tolerated True if the compiler ignores unknown ids here, which
               makes the problem a warning
        """
        report = self.warning if tolerated else self.error
        if value is None:
            report(where, "a %s id is required" % gamedata)
            return
        ids = self.validator.ids_for(gamedata)
        if ids is None:
            return
        if str(value) not in ids:
            report(where, "undefined %s %r" % (gamedata, value))

    def enum(self, ref, value, where):
        """Checks a value against an enum reference from the schema dump."""
        if ref is None:
            return
        if "gamedata" in ref:
            self.reference(ref["gamedata"], value, where)
        elif "array" in ref:
            if value not in ref["array"]:
                self.error(where, "undefined value %r (expected one of: %s)" % (value, ", ".join(ref["array"])))
        elif "hash" in ref:
            if value not in ref["hash"]:
                self.error(where, "undefined value %r (expected one of: %s)" % (value, ", ".join(ref["hash"])))
        elif "module" in ref:
            if value not in ref.get("values", {}):
                self.error(where, "undefined value %r in %s" % (value, ref["module"]))

    def scalar(self, value, letter, enum, where):
        """Checks one value against a schema letter."""
        kind = letter.lower()
        if kind in ("i", "u", "v"):
            if not _is_int(value):
                self.error(where, "must be an integer")
            elif kind == "u" and value < 0:
                self.error(where, "must be 0 or greater")
            elif kind == "v" and value < 1:
                self.error(where, "must be greater than 0")
        elif kind == "f":
            if not isinstance(value, (int, float)) or isinstance(value, bool):
                self.error(where, "must be a number")
        elif kind == "b":
            if not isinstance(value, bool):
                self.error(where, "must be true or false")
        elif kind == "x":
            if not isinstance(value, str) or not _HEX_RE.match(value):
                self.error(where, "must be a hexadecimal number as text")
        elif kind in ("n", "m"):
            if not isinstance(value, str) or not _NAME_RE.match(value):
                self.error(where, "must contain only letters, digits and underscores and not begin with a digit")
        elif kind in ("s", "q"):
            if not isinstance(value, str):
                self.error(where, "must be text")
            elif kind == "s" and "#" in value:
                self.error(where, "can't contain '#' (the compiler treats it as a comment)")
            elif kind == "q" and "#" in value:
                self.error(where, "can't contain '#' (the compiler treats it as a comment)")
        elif kind == "e":
            if not isinstance(value, str):
                self.error(where, "must be text")
            else:
                self.enum(enum, value, where)
        elif kind == "y":
            if _is_int(value):
                return
            if not isinstance(value, str):
                self.error(where, "must be text or an integer")
            else:
                self.enum(enum, value, where)

    def record(self, dataset, field, value, where):
        """Checks one record (a scalar, or an object for multi-value types)."""
        if field.names is None:
            if value is None:
                if not field.letters[0].isupper():
                    self.error(where, "a value is required")
                return
            self.scalar(value, field.letters[0], field.enums[0], where)
            ref = self.validator.config.names.reference(dataset, field.key)
            if ref and isinstance(value, str):
                self.reference(ref, value, where)
            return
        if not isinstance(value, dict):
            self.error(where, "must be an object with keys %s" % ", ".join(field.names))
            return
        self.keys(value, set(field.names), where)
        for name, letter, enum in zip(field.names, field.letters, field.enums):
            sub = (where + "." + name) if where else name
            if value.get(name) is None:
                if not letter.isupper():
                    self.error(sub, "is required")
                continue
            self.scalar(value[name], letter, enum, sub)

    def value(self, dataset, field, value, where):
        """Checks a property value of any shape."""
        if field.is_list:
            if not isinstance(value, list):
                self.error(where, "must be a list")
                return
            for i, item in enumerate(value):
                self.record(dataset, field, item, "%s[%d]" % (where, i))
        else:
            self.record(dataset, field, value, where)

    def group(self, dataset, group, entry, where="", skip=()):
        """Checks an entry (or a nested object) against a FieldGroup."""
        if not isinstance(entry, dict):
            self.error(where, "must be an object")
            return
        allowed = group.known_json_keys() | set(skip)
        self.keys(entry, allowed, where)
        section = group.section_field
        if section is not None and section.names:
            self.record(dataset, section, {n: entry.get(n) for n in section.names}, where)
        elif section is not None:
            self.record(dataset, section, entry.get(section.json_key),
                        (where + "." + section.json_key) if where else section.json_key)
        for key, field in group.property_fields():
            if key in skip or key not in entry:
                continue
            self.value(dataset, field, entry[key], (where + "." + key) if where else key)


class Validator:
    """Validates every dataset of a JSON tree."""

    def __init__(self, config, all_data, src_dir):
        self.config = config
        self.all_data = all_data
        self.src_dir = src_dir
        ## The problems found.
        self.problems = []
        self._ids = {}
        by_name = {d.name: d for d in all_data if not d.subdir}
        for cls, base in config.engine["pbs_files"].items():
            data = by_name.get(base)
            if data is None:
                continue
            ids = set()
            for entry in data.entries():
                if "id" in entry:
                    ids.add(str(entry["id"]))
            self._ids[cls] = ids
        # Forms are species too (e.g. VULPIX_1), as in GameData::Species.
        forms = by_name.get(config.engine["pbs_files"].get("Species1"))
        if forms is not None and "Species" in self._ids:
            for entry in forms.entries():
                if isinstance(entry, dict) and entry.get("species") is not None:
                    self._ids["Species"].add("%s_%s" % (entry["species"], entry.get("form")))
        self._facility_files = {d.name + ".txt" for d in all_data if d.subdir == BATTLE_FACILITY_DIR}

    def _dataset_entries(self, cls):
        """The entries of the dataset for a GameData class (e.g. "Species")."""
        base = self.config.engine["pbs_files"].get(cls)
        data = next((d for d in self.all_data if d.name == base and not d.subdir), None)
        return [] if data is None else [e for e in data.entries() if isinstance(e, dict)]

    def line_root(self, species):
        """The first species of a species' evolution line, as
        GameData::Species#get_baby_species(false) works it out.

        @return the species id, or None if it isn't a species in pokemon.txt
        """
        if not hasattr(self, "_prevolutions"):
            self._species = set()
            self._prevolutions = {}
            for entry in self._dataset_entries("Species"):
                self._species.add(entry.get("id"))
                for evo in entry.get("evolutions", []) or []:
                    if isinstance(evo, dict) and evo.get("species") is not None:
                        self._prevolutions.setdefault(evo["species"], entry.get("id"))
        if species not in self._species:
            return None
        seen = set()
        while species in self._prevolutions and species not in seen:
            seen.add(species)
            species = self._prevolutions[species]
        return species

    def line_patterns(self, species):
        """The pattern ids of a species' evolution line, from pokemon_patterns.

        @return list of ids, or None if the line has no patterns
        """
        if not hasattr(self, "_line_patterns"):
            self._line_patterns = {}
            for entry in self._dataset_entries("PokemonPattern"):
                self._line_patterns[entry.get("id")] = [p.get("id") for p in entry.get("patterns", []) or []
                                                        if isinstance(p, dict)]
        root = self.line_root(species)
        return self._line_patterns.get(root if root is not None else species)

    def ids_for(self, gamedata):
        """The ids defined for a GameData class, or None if unknown."""
        info = self.config.enums.get(gamedata)
        if info and info.get("source") == "hardcoded":
            return set(info.get("values", []))
        return self._ids.get(gamedata)

    def has_battle_facility_file(self, filename):
        return filename in self._facility_files

    def run(self):
        """Runs every check. @return list of Problem"""
        for data in self.all_data:
            if isinstance(data.dataset, RawDataset):
                continue
            default_path = self._dataset_path(data)
            keys = {}
            for f in data.files:
                for entry in f["entries"]:
                    path = data.source_of(entry, default_path)
                    check = EntryChecker(self, path)
                    check.has_battle_facility_file = self.has_battle_facility_file
                    if not isinstance(entry, dict):
                        check.error("", "an entry must be an object")
                        continue
                    data.dataset.validate_entry(entry, check)
                    if isinstance(data.dataset, (BattleFacilityTrainersDataset, BattleFacilityPokemonDataset)):
                        continue
                    try:
                        key = data.dataset.entry_key(entry)
                    except Exception:
                        continue
                    if key in keys:
                        check.error("", "%s [%s] is defined twice (also in %s)" % (data.name, key, keys[key]))
                    else:
                        keys[key] = path
            data.dataset.validate_all(list(data.entries()), EntryChecker(self, default_path))
        self._check_forms()
        for path in orphan_files(self.src_dir, self.all_data):
            self.problems.append(Problem(path, "", "not listed in its folder's _index.json (it won't be exported)"))
        return self.problems

    def _dataset_path(self, data):
        if data.dataset.split:
            return os.path.join(self.src_dir, data.subdir, data.name, "_index.json")
        return os.path.join(self.src_dir, data.subdir, data.name + ".json")

    def _check_forms(self):
        """Forms need their species to be defined (and form numbers above 0)."""
        forms = next((d for d in self.all_data if d.name == self.config.engine["pbs_files"].get("Species1")), None)
        if forms is None:
            return
        for entry in forms.entries():
            if isinstance(entry, dict) and _is_int(entry.get("form")) and entry["form"] < 1:
                path = forms.source_of(entry, self._dataset_path(forms))
                self.problems.append(Problem(path, "form", "form numbers in pokemon_forms must be 1 or greater"))


def validate(config, all_data, src_dir):
    """Validates a loaded JSON tree. @return list of Problem"""
    return Validator(config, all_data, src_dir).run()
