"""@package pbsjson.store
Moves data between a folder of PBS files and the JSON tree in src/pbs.

JSON layout (see docs/PBS_JSON.md):
- src/pbs/<name>.json: a dataset kept in one file:
  {"$schema": ..., "files": [{"suffix": "", "bom": true, "entries": [...]}]}
- src/pbs/<name>/_index.json + src/pbs/<name>/<entry>.json: a dataset with one
  file per entry; the index keeps the order and which PBS file
  (<name>_<suffix>.txt) each entry is in.
- src/pbs/battle_facility/<file>.json: files named by battle_facility_lists.
- src/pbs/_schema/: JSON Schemas for editors (generated).
"""

import hashlib
import json
import os

from .datasets import (BattleFacilityPokemonDataset, BattleFacilityTrainersDataset,
                       BattleFacilityListDataset, RawDataset, build_datasets)
from .pbs_text import BOM, PbsError, read_lines

## Folder (inside src/pbs) for the files named by battle_facility_lists.txt.
BATTLE_FACILITY_DIR = "battle_facility"
## Folder (inside src/pbs) for PBS files the compiler doesn't read, kept as text.
RAW_DIR = "raw"
## Folder (inside src/pbs) for the generated JSON Schemas.
SCHEMA_DIR = "_schema"
## Index file of a split dataset.
INDEX_FILE = "_index.json"
## File (inside the PBS folder) recording what the last export wrote.
STATE_FILE = ".pbs_json_state"


#===============================================================================
# JSON formatting
#===============================================================================
def _is_scalar(value):
    return not isinstance(value, (dict, list))


def _inline(value):
    return json.dumps(value, ensure_ascii=False, separators=(", ", ": "))


def dumps(value, indent=0, top=True):
    """Pretty-prints JSON, keeping short lists and flat objects on one line.

    The output is deterministic so re-importing unchanged data changes no file.
    """
    pad = "  " * indent
    if isinstance(value, (dict, list)) and not top:
        flat = all(_is_scalar(v) for v in (value.values() if isinstance(value, dict) else value))
        if flat:
            text = _inline(value)
            if len(text) + len(pad) <= 100:
                return text
    if isinstance(value, dict):
        if not value:
            return "{}"
        items = ['%s  %s: %s' % (pad, json.dumps(k, ensure_ascii=False), dumps(v, indent + 1, False))
                 for k, v in value.items()]
        return "{\n" + ",\n".join(items) + "\n" + pad + "}"
    if isinstance(value, list):
        if not value:
            return "[]"
        items = ["%s  %s" % (pad, dumps(v, indent + 1, False)) for v in value]
        return "[\n" + ",\n".join(items) + "\n" + pad + "]"
    return json.dumps(value, ensure_ascii=False)


def write_if_changed(path, text):
    """Writes a text file only if its contents change. Returns True if written."""
    data = text.encode("utf-8")
    if os.path.isfile(path):
        with open(path, "rb") as f:
            if f.read() == data:
                return False
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)
    return True


def read_json(path):
    """Reads a JSON file, naming the file in errors."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except ValueError as e:
        raise PbsError("Invalid JSON: %s" % e, path)


def strip_schema_key(obj):
    """Removes the "$schema" key the files carry for editors."""
    if isinstance(obj, dict):
        obj.pop("$schema", None)
    return obj


#===============================================================================
# Datasets in a PBS folder
#===============================================================================
class DatasetData:
    """The contents of one dataset: its PBS files and their entries."""

    def __init__(self, dataset, subdir=""):
        ## The Dataset handler.
        self.dataset = dataset
        ## Folder inside src/pbs ("" or "battle_facility").
        self.subdir = subdir
        ## List of {"suffix": str, "bom": bool, "entries": [entry, ...]}.
        self.files = []
        ## For each entry (by id()), the JSON file it came from, for messages.
        self.sources = {}

    @property
    def name(self):
        return self.dataset.name

    def entries(self):
        """Every entry, in order, across the dataset's PBS files."""
        for f in self.files:
            for entry in f["entries"]:
                yield entry

    def pbs_filename(self, suffix):
        """The PBS file name for a suffix ("pokemon_forms_xxx.txt")."""
        return "%s_%s.txt" % (self.name, suffix) if suffix else "%s.txt" % self.name

    def source_of(self, entry, default):
        return self.sources.get(id(entry), default)


def _match_pbs_files(names, bases):
    """Matches PBS file names to base filenames the way the compiler does.

    @return dict base -> list of (file name, suffix), and unmatched names
    """
    order = sorted(bases, key=lambda b: -len(b))
    matched = {b: [] for b in bases}
    unmatched = []
    for name in sorted(names):
        stem = name[:-4]
        for base in order:
            if stem == base:
                matched[base].append((name, ""))
                break
            if stem.startswith(base + "_"):
                matched[base].append((name, stem[len(base) + 1:]))
                break
        else:
            unmatched.append(name)
    return matched, unmatched


def read_pbs_dir(config, pbs_dir, warn):
    """Reads every PBS file in a folder (not its subfolders, e.g. backups).

    @return list of DatasetData, in compile order
    """
    datasets = build_datasets(config)
    names = sorted(n for n in os.listdir(pbs_dir)
                   if n.lower().endswith(".txt") and os.path.isfile(os.path.join(pbs_dir, n)))
    result = []

    def read_one(dataset, filename, suffix, data):
        path = os.path.join(pbs_dir, filename)
        lines, bom = read_lines(path)
        entries = dataset.parse_file(lines, path, warn)
        data.files.append({"suffix": suffix, "bom": bom, "entries": entries})

    # battle_facility_lists.txt names the trainer/Pokémon files it uses.
    facility_files = {}
    facility_name = None
    for name, dataset in datasets.items():
        if isinstance(dataset, BattleFacilityListDataset):
            facility_name = name
    if facility_name and (facility_name + ".txt") in names:
        lists = datasets[facility_name]
        path = os.path.join(pbs_dir, facility_name + ".txt")
        lines, _ = read_lines(path)
        trainers, pokemon = lists.referenced_files(lists.parse_file(lines, path, lambda m: None))
        for fname in trainers:
            facility_files[fname] = BattleFacilityTrainersDataset(config, fname[:-4] if fname.endswith(".txt") else fname)
        for fname in pokemon:
            if fname not in facility_files:
                facility_files[fname] = BattleFacilityPokemonDataset(config, fname[:-4] if fname.endswith(".txt") else fname)

    regular = [n for n in names if n not in facility_files]
    matched, unmatched = _match_pbs_files(regular, list(datasets.keys()))
    for name, dataset in datasets.items():
        if not matched[name]:
            continue
        data = DatasetData(dataset)
        for filename, suffix in matched[name]:
            read_one(dataset, filename, suffix, data)
        result.append(data)
    for fname, dataset in facility_files.items():
        if fname not in names:
            warn("%s names %s, which doesn't exist." % (facility_name + ".txt", fname))
            continue
        data = DatasetData(dataset, BATTLE_FACILITY_DIR)
        read_one(dataset, fname, "", data)
        result.append(data)
    for name in unmatched:
        warn("%s is not a PBS file the compiler reads; kept as text in src/pbs/%s/." % (name, RAW_DIR))
        data = DatasetData(RawDataset(config, name[:-4]), RAW_DIR)
        data.files.append({"suffix": "", "bom": False,
                           "entries": RawDataset(config, name).parse_file(None, os.path.join(pbs_dir, name), warn)})
        result.append(data)
    return result


#===============================================================================
# JSON tree
#===============================================================================
def _schema_ref(depth, name):
    return "/".join([".."] * depth + [SCHEMA_DIR, name])


def _dataset_json_path(src_dir, data):
    base = os.path.join(src_dir, data.subdir) if data.subdir else src_dir
    if data.dataset.split:
        return os.path.join(base, data.name)
    return os.path.join(base, data.name + ".json")


def _schema_name(data):
    prefix = data.subdir + "." if data.subdir else ""
    if isinstance(data.dataset, BattleFacilityTrainersDataset):
        return "battle_facility_trainers"
    if isinstance(data.dataset, BattleFacilityPokemonDataset):
        return "battle_facility_pokemon"
    return prefix + data.name


def write_json_tree(src_dir, all_data, log):
    """Writes datasets as JSON, removing JSON files of entries that are gone.

    @return number of files written or removed
    """
    changed = 0
    raw_dir = os.path.join(src_dir, RAW_DIR)
    raw_wanted = set()
    for data in all_data:
        if isinstance(data.dataset, RawDataset):
            raw_wanted.add(data.name + ".txt")
            if write_if_changed(os.path.join(raw_dir, data.name + ".txt"), data.files[0]["entries"][0]):
                changed += 1
    if os.path.isdir(raw_dir):
        for name in sorted(os.listdir(raw_dir)):
            if name.endswith(".txt") and name not in raw_wanted:
                os.remove(os.path.join(raw_dir, name))
                log("Removed %s (its PBS file no longer exists)." % os.path.join(raw_dir, name))
                changed += 1
    for data in all_data:
        if isinstance(data.dataset, RawDataset):
            continue
        depth = 1 if data.subdir else 0
        path = _dataset_json_path(src_dir, data)
        schema = _schema_name(data)
        if not data.dataset.split:
            doc = {"$schema": _schema_ref(depth, schema + ".schema.json"), "files": data.files}
            if write_if_changed(path, dumps(doc) + "\n"):
                changed += 1
            continue
        os.makedirs(path, exist_ok=True)
        index_files = []
        used = set()
        wanted = {INDEX_FILE}
        for f in data.files:
            stems = []
            for entry in f["entries"]:
                stem = data.dataset.entry_stem(entry)
                n = 2
                unique = stem
                while unique in used:
                    unique = "%s_%d" % (stem, n)
                    n += 1
                used.add(unique)
                stems.append(unique)
                doc = {"$schema": _schema_ref(depth + 1, schema + ".entry.schema.json")}
                doc.update(entry)
                wanted.add(unique + ".json")
                if write_if_changed(os.path.join(path, unique + ".json"), dumps(doc) + "\n"):
                    changed += 1
            index_files.append({"suffix": f["suffix"], "bom": f["bom"], "entries": stems})
        index = {"$schema": _schema_ref(depth + 1, "index.schema.json"), "files": index_files}
        if write_if_changed(os.path.join(path, INDEX_FILE), dumps(index) + "\n"):
            changed += 1
        for name in sorted(os.listdir(path)):
            if name.endswith(".json") and name not in wanted:
                os.remove(os.path.join(path, name))
                log("Removed %s (no longer in the PBS file)." % os.path.join(path, name))
                changed += 1
    return changed


def remove_missing_datasets(src_dir, config, all_data, log):
    """Removes JSON datasets whose PBS files no longer exist."""
    present = {_dataset_json_path(src_dir, d) for d in all_data}
    datasets = build_datasets(config)
    candidates = []
    for name, dataset in datasets.items():
        candidates.append(os.path.join(src_dir, name))
        candidates.append(os.path.join(src_dir, name + ".json"))
    facility = os.path.join(src_dir, BATTLE_FACILITY_DIR)
    if os.path.isdir(facility):
        candidates += [os.path.join(facility, n) for n in os.listdir(facility) if n.endswith(".json")]
    for path in candidates:
        if path in present or not os.path.exists(path):
            continue
        if os.path.isdir(path):
            for name in os.listdir(path):
                os.remove(os.path.join(path, name))
            os.rmdir(path)
        else:
            os.remove(path)
        log("Removed %s (its PBS file no longer exists)." % path)


def load_json_tree(config, src_dir):
    """Reads the JSON tree into DatasetData, in compile order.

    @throws PbsError if a file is missing or isn't valid JSON
    """
    datasets = build_datasets(config)
    result = []
    for name, dataset in datasets.items():
        data = DatasetData(dataset)
        if dataset.split:
            folder = os.path.join(src_dir, name)
            index_path = os.path.join(folder, INDEX_FILE)
            if not os.path.isfile(index_path):
                continue
            index = strip_schema_key(read_json(index_path))
            for f in index.get("files", []):
                entries = []
                for stem in f.get("entries", []):
                    path = os.path.join(folder, stem + ".json")
                    if not os.path.isfile(path):
                        raise PbsError("%s lists %s, which doesn't exist." % (index_path, stem + ".json"), path)
                    entry = strip_schema_key(read_json(path))
                    data.sources[id(entry)] = path
                    entries.append(entry)
                data.files.append({"suffix": f.get("suffix", ""), "bom": f.get("bom", True), "entries": entries})
            data.index_path = index_path
        else:
            path = os.path.join(src_dir, name + ".json")
            if not os.path.isfile(path):
                continue
            doc = strip_schema_key(read_json(path))
            for f in doc.get("files", []):
                for entry in f.get("entries", []):
                    data.sources[id(entry)] = path
                data.files.append({"suffix": f.get("suffix", ""), "bom": f.get("bom", True),
                                   "entries": f.get("entries", [])})
        result.append(data)
    facility = os.path.join(src_dir, BATTLE_FACILITY_DIR)
    lists = next((d for d in result if isinstance(d.dataset, BattleFacilityListDataset)), None)
    if lists is not None:
        trainers, pokemon = lists.dataset.referenced_files(list(lists.entries()))
        kinds = [(f, BattleFacilityTrainersDataset) for f in trainers]
        kinds += [(f, BattleFacilityPokemonDataset) for f in pokemon if f not in trainers]
        for fname, cls in kinds:
            stem = fname[:-4] if fname.endswith(".txt") else fname
            path = os.path.join(facility, stem + ".json")
            if not os.path.isfile(path):
                continue
            data = DatasetData(cls(config, stem), BATTLE_FACILITY_DIR)
            doc = strip_schema_key(read_json(path))
            for f in doc.get("files", []):
                for entry in f.get("entries", []):
                    data.sources[id(entry)] = path
                data.files.append({"suffix": "", "bom": f.get("bom", True), "entries": f.get("entries", [])})
            result.append(data)
    raw_dir = os.path.join(src_dir, RAW_DIR)
    if os.path.isdir(raw_dir):
        for name in sorted(os.listdir(raw_dir)):
            if not name.endswith(".txt"):
                continue
            dataset = RawDataset(config, name[:-4])
            data = DatasetData(dataset, RAW_DIR)
            data.files.append({"suffix": "", "bom": False,
                               "entries": dataset.parse_file(None, os.path.join(raw_dir, name), None)})
            result.append(data)
    return result


def orphan_files(src_dir, all_data):
    """JSON entry files in split folders that no index lists."""
    result = []
    for data in all_data:
        if not data.dataset.split:
            continue
        folder = _dataset_json_path(src_dir, data)
        listed = {os.path.normpath(p) for p in data.sources.values()}
        for name in sorted(os.listdir(folder)):
            path = os.path.normpath(os.path.join(folder, name))
            if name.endswith(".json") and name != INDEX_FILE and path not in listed:
                result.append(path)
    return result


#===============================================================================
# Writing PBS files
#===============================================================================
def render_pbs(all_data):
    """The text of every PBS file. @return dict file name -> bytes"""
    result = {}
    for data in all_data:
        for f in data.files:
            text = data.dataset.write_file(f["entries"])
            if f.get("bom", True):
                text = BOM + text
            filename = data.pbs_filename(f["suffix"]) if not data.subdir else data.name + ".txt"
            result[filename] = text.encode("utf-8")
    return result


def _sha1(data):
    return hashlib.sha1(data).hexdigest()


def load_state(pbs_dir):
    """The hashes of the files the last export wrote to a PBS folder."""
    path = os.path.join(pbs_dir, STATE_FILE)
    if not os.path.isfile(path):
        return None
    try:
        return read_json(path).get("files", {})
    except PbsError:
        return None


def save_state(pbs_dir, files):
    """Records the hashes of the PBS files that match src/pbs."""
    write_if_changed(os.path.join(pbs_dir, STATE_FILE),
                     dumps({"files": dict(sorted(files.items()))}) + "\n")


def export_pbs(rendered, pbs_dir, force, log):
    """Writes PBS files, refusing to overwrite files changed since the last export.

    A file changed by the in-game debug editors (it differs from what the last
    export wrote) is a conflict: import it with `make pull-pbs` first, or pass
    force to overwrite it.

    @return (written, conflicts)
    """
    os.makedirs(pbs_dir, exist_ok=True)
    state = load_state(pbs_dir)
    conflicts = []
    for name, data in rendered.items():
        path = os.path.join(pbs_dir, name)
        if not os.path.isfile(path) or state is None:
            continue
        with open(path, "rb") as f:
            current = f.read()
        if current == data:
            continue
        if state.get(name) != _sha1(current):
            conflicts.append(name)
    if conflicts and not force:
        return 0, conflicts
    written = 0
    new_state = {}
    for name, data in rendered.items():
        if write_if_changed(os.path.join(pbs_dir, name), data.decode("utf-8")):
            written += 1
        new_state[name] = _sha1(data)
    # Remove PBS files an earlier export wrote that src/pbs no longer has.
    for name in sorted((state or {}).keys()):
        if name in rendered:
            continue
        path = os.path.join(pbs_dir, name)
        if os.path.isfile(path):
            os.remove(path)
            log("Removed %s (no longer in src/pbs)." % path)
            written += 1
    save_state(pbs_dir, new_state)
    return written, conflicts


def accept_pbs_dir(pbs_dir, names):
    """After importing a PBS folder that an export wrote, records its current
    files as in sync, so the next export may overwrite them."""
    state = load_state(pbs_dir)
    if state is None:
        return
    for name in names:
        path = os.path.join(pbs_dir, name)
        if os.path.isfile(path):
            with open(path, "rb") as f:
                state[name] = _sha1(f.read())
    save_state(pbs_dir, state)
