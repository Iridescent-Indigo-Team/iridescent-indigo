"""@package tiledc.registry
The map registry (src/tiled/maps/registry.json): stable map ids, names, files
and the map tree. It replaces RMXP's MapInfos.rxdata.

Format:
@code
{
 "maps": [
  {"id": 2, "file": "002_lappet_town.tmj", "name": "Lappet Town",
   "parent": 0, "order": 2, "expanded": false}
 ]
}
@endcode
"""

import os
import re
import unicodedata

from .problems import TiledError
from .tiledio import load_json, save_json


def slug(name):
    """A file-name-safe version of a map name ("Lappet Town" -> "lappet_town")."""
    text = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode("ascii")
    text = re.sub(r"[^A-Za-z0-9]+", "_", text).strip("_").lower()
    return text or "map"


class Registry:
    """The maps of a game."""

    def __init__(self, path, entries=None):
        ## Registry file.
        self.path = path
        ## Entries, sorted by id.
        self.entries = sorted(entries or [], key=lambda e: e["id"])

    @classmethod
    def load(cls, path):
        """@throws TiledError if the file is missing or invalid"""
        doc = load_json(path)
        entries = doc.get("maps")
        if not isinstance(entries, list):
            raise TiledError("%s has no \"maps\" list." % path)
        return cls(path, entries)

    def save(self):
        """Writes the registry. @return True if it changed"""
        entries = []
        for e in sorted(self.entries, key=lambda e: e["id"]):
            ordered = {"id": e["id"], "file": e["file"], "name": e.get("name", ""),
                       "parent": e.get("parent", 0), "order": e.get("order", e["id"]),
                       "expanded": bool(e.get("expanded", False))}
            for k in ("scroll_x", "scroll_y"):
                if e.get(k):
                    ordered[k] = e[k]
            entries.append(ordered)
        return save_json(self.path, {"maps": entries})

    def folder(self):
        """Folder the map files are in."""
        return os.path.dirname(os.path.abspath(self.path))

    def map_path(self, entry):
        """Absolute path of an entry's .tmj."""
        return os.path.join(self.folder(), entry["file"])

    def by_id(self, map_id):
        return next((e for e in self.entries if e["id"] == map_id), None)

    def by_name(self, name):
        """The first map with this name (names don't have to be unique)."""
        return next((e for e in self.entries if e.get("name") == name), None)

    def by_file(self, path):
        full = os.path.normcase(os.path.abspath(path))
        return next((e for e in self.entries
                     if os.path.normcase(self.map_path(e)) == full), None)

    def next_id(self):
        """The lowest unused id above every existing one."""
        return max([e["id"] for e in self.entries] + [0]) + 1

    def add(self, name, file=None, parent=0, map_id=None):
        """Registers a new map. @return the entry"""
        map_id = self.next_id() if map_id is None else map_id
        if self.by_id(map_id):
            raise TiledError("Map id %d is already used by %s." % (map_id, self.by_id(map_id)["file"]))
        entry = {"id": map_id, "file": file or "%03d_%s.tmj" % (map_id, slug(name)), "name": name,
                 "parent": parent, "order": map_id, "expanded": False}
        self.entries.append(entry)
        self.entries.sort(key=lambda e: e["id"])
        return entry

    def name_to_id(self):
        """Map name -> id (first map wins for duplicate names), plus file stems."""
        result = {}
        for e in self.entries:
            result.setdefault(e.get("name", ""), e["id"])
            result.setdefault(os.path.splitext(e["file"])[0], e["id"])
        return result

    def mapinfos(self):
        """The MapInfos.rxdata content for the Ruby back end."""
        return {str(e["id"]): {"name": e.get("name", ""), "parent_id": e.get("parent", 0),
                               "order": e.get("order", e["id"]), "expanded": bool(e.get("expanded")),
                               "scroll_x": e.get("scroll_x", 0), "scroll_y": e.get("scroll_y", 0)}
                for e in self.entries}
