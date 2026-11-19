"""@package pbsjson.config
Loads the engine schema dump and the hand-written names.json/layout.json.
"""

import json
import os

## Folder of the converter (tools/importer/pbs).
TOOL_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
## Default path of the schema dumped by the engine.
ENGINE_SCHEMA = os.path.join(TOOL_DIR, "engine_schema.json")
## Hand-written tuple names, aliases and references.
NAMES_FILE = os.path.join(TOOL_DIR, "names.json")
## Hand-written list of datasets split into one JSON file per entry.
LAYOUT_FILE = os.path.join(TOOL_DIR, "layout.json")


def _load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


class Names:
    """names.json: tuple names, PBS key aliases and id references."""

    def __init__(self, data):
        self._tuples = data.get("tuples", {})
        self._aliases = data.get("aliases", {})
        self._references = data.get("references", {})

    def tuple_names(self, dataset, key):
        """Names for a multi-value field, or None if names.json has none."""
        return self._tuples.get("%s.%s" % (dataset, key), self._tuples.get(key))

    def aliases(self, dataset):
        """Old PBS key -> current PBS key for a dataset."""
        return dict(self._aliases.get(dataset, {}))

    def reference(self, dataset, key):
        """The GameData class a field's values must be ids of, or None."""
        return self._references.get("%s.%s" % (dataset, key))


class Config:
    """Everything the converter needs to know about the PBS formats."""

    def __init__(self, engine_schema=ENGINE_SCHEMA, names=NAMES_FILE, layout=LAYOUT_FILE):
        if not os.path.isfile(engine_schema):
            raise FileNotFoundError(
                "%s doesn't exist. Run `make pbs-schema` to dump it from the engine." % engine_schema)
        ## The engine schema dump (see Compiler.dump_pbs_schema).
        self.engine = _load_json(engine_schema)
        ## names.json.
        self.names = Names(_load_json(names))
        ## Names of the datasets split into one file per entry.
        self.split = set(_load_json(layout).get("split", []))

    @property
    def classes(self):
        """GameData class name -> class info from the dump."""
        return self.engine["classes"]

    @property
    def enums(self):
        """Enum name -> {"source": "pbs"|"hardcoded", "values": [...]}."""
        return self.engine["enums"]

    @property
    def extra(self):
        """Extra engine data (evolution parameters, encounter types, ...)."""
        return self.engine.get("extra", {})

    def class_for_file(self, base):
        """The GameData class name whose PBS base filename is base, or None."""
        for key, value in self.engine["pbs_files"].items():
            if value == base:
                return key
        return None
