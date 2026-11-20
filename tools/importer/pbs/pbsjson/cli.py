"""@package pbsjson.cli
Command line: import, export, validate, schema and roundtrip.
"""

import argparse
import os
import shutil
import sys
import tempfile

from .config import ENGINE_SCHEMA, Config
from .jsonschema_gen import write_schemas
from .pbs_text import PbsError
from .store import (accept_pbs_dir, export_pbs, load_json_tree, read_pbs_dir, remove_missing_datasets,
                    render_pbs, write_json_tree)
from .validate import validate

## The repository root.
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))))))
## Default JSON tree.
DEFAULT_SRC = os.path.join(ROOT, "src", "pbs")


def _log(message):
    print(message)


def _warn(message):
    print("warning: " + message, file=sys.stderr)


def cmd_import(config, args):
    """PBS folder -> src/pbs."""
    if not os.path.isdir(args.pbs_dir):
        raise PbsError("%s is not a folder." % args.pbs_dir)
    all_data = read_pbs_dir(config, args.pbs_dir, _warn)
    skip = set(filter(None, (args.skip or "").split(",")))
    if skip:
        # Datasets owned by another source (the Tiled maps) are left alone.
        all_data = [d for d in all_data if d.name not in skip]
    changed = write_json_tree(args.src, all_data, _log)
    remove_missing_datasets(args.src, config, all_data, _log, keep=skip)
    write_schemas(config, args.src)
    imported = []
    for data in all_data:
        for f in data.files:
            imported.append(data.pbs_filename(f["suffix"]) if not data.subdir else data.name + ".txt")
    accept_pbs_dir(args.pbs_dir, imported)
    entries = sum(len(f["entries"]) for d in all_data for f in d.files)
    print("Imported %d PBS files (%d entries) from %s into %s; %d JSON files changed."
          % (len(imported), entries, args.pbs_dir, args.src, changed))
    return 0


def _load_and_validate(config, src):
    if not os.path.isdir(src):
        raise PbsError("%s doesn't exist. Run `make import-pbs` first." % src)
    all_data = load_json_tree(config, src)
    problems = validate(config, all_data, src)
    return all_data, problems


def _report(problems, limit=200):
    """Prints problems. @return the errors (problems that aren't warnings)"""
    for p in problems[:limit]:
        print("%s: %s" % ("warning" if p.warning else "error", p), file=sys.stderr)
    if len(problems) > limit:
        print("... and %d more" % (len(problems) - limit), file=sys.stderr)
    return [p for p in problems if not p.warning]


def cmd_validate(config, args):
    """Checks src/pbs."""
    all_data, problems = _load_and_validate(config, args.src)
    errors = _report(problems)
    if errors:
        print("%d errors found in %s." % (len(errors), args.src), file=sys.stderr)
        return 1
    entries = sum(len(f["entries"]) for d in all_data for f in d.files)
    print("%s is valid (%d datasets, %d entries)." % (args.src, len(all_data), entries))
    return 0


def cmd_export(config, args):
    """src/pbs -> PBS folder."""
    all_data, problems = _load_and_validate(config, args.src)
    errors = _report(problems)
    if errors and not args.no_validate:
        print("Not exporting: %d errors found in %s (see above)." % (len(errors), args.src), file=sys.stderr)
        return 1
    rendered = render_pbs(all_data)
    written, conflicts = export_pbs(rendered, args.pbs_dir, args.force, _log)
    if conflicts and not args.force:
        for name in conflicts:
            print("conflict: %s was changed in %s since the last export (by the in-game "
                  "editors?)." % (name, args.pbs_dir), file=sys.stderr)
        print("Not exporting. Run `make pull-pbs` to import those changes into %s first, or "
              "export with --force (FORCE=1) to overwrite them." % args.src, file=sys.stderr)
        return 2
    print("Exported %d PBS files to %s (%d changed)." % (len(rendered), args.pbs_dir, written))
    return 0


def cmd_schema(config, args):
    """Regenerates src/pbs/_schema."""
    written = write_schemas(config, args.src)
    print("Wrote JSON Schemas to %s (%d changed)." % (os.path.join(args.src, "_schema"), written))
    return 0


def cmd_roundtrip(config, args):
    """PBS -> JSON -> PBS -> JSON, checking nothing is lost."""
    tmp = tempfile.mkdtemp(prefix="pbs_json_")
    try:
        src1 = os.path.join(tmp, "json1")
        pbs = os.path.join(tmp, "pbs")
        src2 = os.path.join(tmp, "json2")
        data1 = read_pbs_dir(config, args.pbs_dir, _warn)
        write_json_tree(src1, data1, lambda m: None)
        loaded = load_json_tree(config, src1)
        problems = validate(config, loaded, src1)
        export_pbs(render_pbs(loaded), pbs, True, lambda m: None)
        data2 = read_pbs_dir(config, pbs, _warn)
        write_json_tree(src2, data2, lambda m: None)
        diffs = []
        for dirpath, _, files in os.walk(src1):
            for name in files:
                a = os.path.join(dirpath, name)
                b = os.path.join(src2, os.path.relpath(a, src1))
                if not os.path.isfile(b) or open(a, "rb").read() != open(b, "rb").read():
                    diffs.append(os.path.relpath(a, src1))
        for d in diffs:
            print("differs after a round trip: %s" % d, file=sys.stderr)
        errors = _report(problems)
        print("Round trip of %s: %d JSON files differ, %d validation errors, %d warnings."
              % (args.pbs_dir, len(diffs), len(errors), len(problems) - len(errors)))
        return 1 if diffs else 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="pbs_json.py", description="Convert Pokémon Essentials PBS files to JSON and back.")
    parser.add_argument("--engine-schema", default=ENGINE_SCHEMA,
                        help="schema dumped by the engine (default: %(default)s)")
    parser.add_argument("--src", default=DEFAULT_SRC, help="JSON folder (default: src/pbs)")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("import", help="read a PBS folder into the JSON folder")
    p.add_argument("pbs_dir", help="folder of PBS .txt files (subfolders such as backups are ignored)")
    p.add_argument("--skip", default="", help="comma-separated datasets to leave alone (e.g. the ones "
                   "the Tiled maps own)")
    p.set_defaults(func=cmd_import)

    p = sub.add_parser("export", help="validate the JSON folder and write PBS files")
    p.add_argument("pbs_dir", help="folder to write PBS .txt files into")
    p.add_argument("--force", action="store_true", help="overwrite PBS files changed since the last export")
    p.add_argument("--no-validate", action="store_true", help="export even if validation fails")
    p.set_defaults(func=cmd_export)

    p = sub.add_parser("validate", help="check the JSON folder")
    p.set_defaults(func=cmd_validate)

    p = sub.add_parser("schema", help="regenerate the JSON Schemas in <src>/_schema")
    p.set_defaults(func=cmd_schema)

    p = sub.add_parser("roundtrip", help="check that PBS -> JSON -> PBS loses nothing")
    p.add_argument("pbs_dir")
    p.set_defaults(func=cmd_roundtrip)

    args = parser.parse_args(argv)
    try:
        config = Config(engine_schema=args.engine_schema)
        return args.func(config, args)
    except (PbsError, FileNotFoundError) as e:
        print("error: %s" % e, file=sys.stderr)
        return 1
