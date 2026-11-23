"""@package tiledc.cli
Command line of tiled_compiler.py.
"""

import argparse
import csv
import io
import json
import os
import subprocess
import sys

from . import config, events
from .compiler import compile_project
from .problems import TiledError


def _log(message):
    print(message)


def _warn(message):
    print("warning: " + message, file=sys.stderr)


def _report(problems, strict=False, limit=200):
    """Prints problems. @return the problems that fail the command"""
    items = problems.items
    for p in items[:limit]:
        print("%s: %s" % ("warning" if p.warning else "error", p), file=sys.stderr)
    if len(items) > limit:
        print("... and %d more" % (len(items) - limit), file=sys.stderr)
    return problems.errors(strict)


def cmd_build(paths, args):
    """src/tiled -> build/Data, build/Graphics, build/.tiled/pbs."""
    build = os.path.abspath(args.build)
    problems = compile_project(paths, os.path.join(build, "Data"), os.path.join(build, "Graphics"),
                               os.path.join(build, ".tiled", "pbs"), ruby=args.ruby, force=args.force, log=_log)
    failed = _report(problems, args.strict)
    if failed:
        print("Tiled: %d problems; nothing was written (see above)." % len(failed), file=sys.stderr)
        return 1
    return 0


def cmd_validate(paths, args):
    """Checks src/tiled, including the event scripts."""
    problems = compile_project(paths, check_only=True, ruby=args.ruby, log=_log)
    failed = _report(problems, args.strict)
    if failed:
        print("%d problems found in %s." % (len(failed), paths.rel(paths.src)), file=sys.stderr)
        return 1
    print("%s is valid (%d warnings)." % (paths.rel(paths.src), len(problems.items)))
    return 0


def cmd_import(paths, args):
    """RMXP data -> src/tiled."""
    from .importer import import_rxdata
    from .project import write_project
    import_rxdata(paths, args.data_dir, ruby=args.ruby, force=args.force, keep_pbs=args.keep_pbs,
                  log=_log, warn=_warn)
    write_project(paths)
    return 0


def cmd_project(paths, args):
    from .project import write_project
    changed = write_project(paths)
    print("%s %s." % (paths.rel(paths.project), "updated" if changed else "is up to date"))
    return 0


def cmd_autotiles(paths, args):
    """Converts RMXP autotiles (Graphics/Autotiles) into Tiled tilesets."""
    from .autotiles import convert
    from .registry import slug
    from .tiledio import load_json, props
    folder = os.path.join(config.GRAPHICS, "Autotiles")
    targets = {}
    if os.path.isdir(paths.autotiles):
        for name in sorted(os.listdir(paths.autotiles)):
            if name.endswith(".tsj"):
                doc = load_json(os.path.join(paths.autotiles, name))
                targets[name[:-4]] = props(doc).get("autotile") or doc.get("name")
    if args.names:
        for n in args.names:
            if n not in targets.values():
                targets[slug(n)] = n
    elif args.all and os.path.isdir(folder):
        for n in sorted(os.listdir(folder)):
            if n.lower().endswith(".png") and os.path.splitext(n)[0] not in targets.values():
                targets[slug(os.path.splitext(n)[0])] = os.path.splitext(n)[0]
    done = 0
    for stem, name in sorted(targets.items()):
        src = os.path.join(folder, name + ".png")
        if not os.path.isfile(src):
            _warn("Graphics/Autotiles/%s.png not found (install the graphics first)" % name)
            continue
        convert(src, paths.autotiles, name, stem)
        done += 1
    print("Converted %d autotiles into %s." % (done, paths.rel(paths.autotiles)))
    return 0


def cmd_downscale(paths, args):
    """Converts a src/tiled made for 2x graphics (32px tiles) to 1x (16px)."""
    from .downscale import downscale
    downscale(paths, log=_log)
    return 0


def cmd_previews(paths, args):
    from .previews import write_previews
    count = write_previews(paths)
    print("Wrote %d event previews into %s." % (count, paths.rel(paths.generated)))
    return 0


def _registry_map(paths, name):
    from .registry import Registry
    reg = Registry.load(paths.registry)
    entry = reg.by_id(int(name)) if str(name).isdigit() else (reg.by_name(name) or reg.by_file(name))
    if entry is None:
        raise TiledError("no map %r in the registry" % name)
    return reg, entry


def cmd_new_map(paths, args):
    """Registers and creates an empty map."""
    from .registry import Registry
    from .newmap import new_map
    reg = Registry.load(paths.registry) if paths.exists() else Registry(paths.registry, [])
    path = new_map(paths, reg, args.name, args.width, args.height, args.tileset, args.parent)
    print("Created %s." % paths.rel(path))
    return 0


def cmd_export_events(paths, args):
    """Map events -> standalone .rb files."""
    from .tiledio import load_json, props
    reg, entry = _registry_map(paths, args.map)
    map_path = reg.map_path(entry)
    data = load_json(map_path)
    os.makedirs(args.out_dir, exist_ok=True)
    count = 0
    for _, obj in events.map_objects(data):
        if not events.is_event(obj):
            continue
        eid = props(obj).get("event_id") or obj.get("id")
        if args.event and eid not in args.event:
            continue
        script = events.event_script_path(map_path, obj)
        text = open(script, encoding="utf-8").read() if script and os.path.isfile(script) else ""
        out = os.path.join(args.out_dir, events.script_file_name(eid, obj.get("name", "")))
        with open(out, "w", encoding="utf-8") as f:
            f.write(events.export_event(obj, text))
        count += 1
    print("Exported %d events to %s." % (count, args.out_dir))
    return 0


def cmd_import_events(paths, args):
    """Standalone .rb files -> map events."""
    from .tiledio import load_json, save_json
    reg, entry = _registry_map(paths, args.map)
    map_path = reg.map_path(entry)
    data = load_json(map_path)
    for file in args.files:
        with open(file, encoding="utf-8") as f:
            obj = events.import_event(data, map_path, paths, f.read(), args.x, args.y)
        print("Added event %s (%r)." % (obj["properties"][0]["value"], obj["name"]))
    save_json(map_path, data)
    return 0


def cmd_export_tiledata(paths, args):
    from .importer import export_tile_data
    export_tile_data(args.tileset, args.out)
    print("Wrote %s." % args.out)
    return 0


def cmd_import_tiledata(paths, args):
    from .importer import import_tile_data
    import_tile_data(paths, args.tileset, args.source, ruby=args.ruby, rmxp_id=args.tileset_id, log=_log)
    return 0


def cmd_text(paths, args):
    """Every message and choice of the compiled maps -> CSV (for proofreading)."""
    data_dir = os.path.join(os.path.abspath(args.build), "Data")
    script = os.path.join(config.ROOT, "tools", "importer", "locales", "extract_events.rb")
    proc = subprocess.run([args.ruby, script, data_dir, "--compiled"], stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE)
    if proc.returncode != 0:
        raise TiledError("extract_events.rb failed (run `make tiled` first):\n"
                         + proc.stderr.decode("utf-8", "replace"))
    doc = json.loads(proc.stdout.decode("utf-8"))
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\n")
    w.writerow(["map", "map_name", "event", "page", "kind", "text"])
    for t in doc.get("texts", []):
        w.writerow([t.get("map"), doc.get("maps", {}).get(str(t.get("map")), ""), t.get("event"),
                    t.get("page"), t.get("kind"), t.get("text")])
    out = args.out
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        f.write(buf.getvalue())
    print("Wrote %d texts to %s." % (len(doc.get("texts", [])), out))
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(prog="tiled_compiler.py",
                                     description="Compile Tiled maps into Pokessentials data, and import "
                                                 "RPG Maker XP data into Tiled.")
    parser.add_argument("--src", default=config.DEFAULT_SRC, help="Tiled source folder (default: src/tiled)")
    parser.add_argument("--graphics", default=None, help="source graphics (default: src/assets/graphics)")
    parser.add_argument("--ruby", default=os.environ.get("RUBY", "ruby"), help="Ruby interpreter")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("build", help="validate and compile src/tiled into the build folder")
    p.add_argument("--build", default=os.path.join(config.ROOT, "build"), help="build folder")
    p.add_argument("--force", action="store_true", help="rebuild everything")
    p.add_argument("--strict", action="store_true", help="fail on warnings too")
    p.set_defaults(func=cmd_build)

    p = sub.add_parser("validate", help="check src/tiled, including event scripts")
    p.add_argument("--strict", action="store_true", help="fail on warnings too")
    p.set_defaults(func=cmd_validate)

    p = sub.add_parser("import", help="import RPG Maker XP data into src/tiled")
    p.add_argument("data_dir", nargs="?", default=os.path.join(config.ROOT, "src", "assets", "data"))
    p.add_argument("--force", action="store_true", help="overwrite an existing src/tiled")
    p.add_argument("--keep-pbs", action="store_true", help="keep the map datasets in src/pbs")
    p.set_defaults(func=cmd_import)

    p = sub.add_parser("project", help="regenerate the Tiled project's custom types")
    p.set_defaults(func=cmd_project)

    p = sub.add_parser("autotiles", help="convert RMXP autotiles into Tiled tilesets")
    p.add_argument("names", nargs="*", help="autotile names (default: the ones already converted)")
    p.add_argument("--all", action="store_true", help="convert every autotile in Graphics/Autotiles")
    p.set_defaults(func=cmd_autotiles)

    p = sub.add_parser("previews", help="make the images Tiled shows for event graphics")
    p.set_defaults(func=cmd_previews)

    p = sub.add_parser("downscale", help="one-time: convert a src/tiled with 32px tiles (2x graphics) to 16px")
    p.set_defaults(func=cmd_downscale)

    p = sub.add_parser("new-map", help="register and create an empty map")
    p.add_argument("name")
    p.add_argument("--width", type=int, default=20)
    p.add_argument("--height", type=int, default=15)
    p.add_argument("--tileset", action="append", default=[], help=".tsj to use (repeatable)")
    p.add_argument("--parent", type=int, default=0)
    p.set_defaults(func=cmd_new_map)

    p = sub.add_parser("export-events", help="write a map's events as standalone .rb files")
    p.add_argument("map", help="map id, name or file")
    p.add_argument("out_dir")
    p.add_argument("--event", type=int, action="append", help="only this event id (repeatable)")
    p.set_defaults(func=cmd_export_events)

    p = sub.add_parser("import-events", help="add standalone event .rb files to a map")
    p.add_argument("map", help="map id, name or file")
    p.add_argument("files", nargs="+")
    p.add_argument("--x", type=int, default=None)
    p.add_argument("--y", type=int, default=None)
    p.set_defaults(func=cmd_import_events)

    p = sub.add_parser("export-tiledata", help="write a tileset's tile data as .json or .csv")
    p.add_argument("tileset", help=".tsj file")
    p.add_argument("out", help="output .json or .csv")
    p.set_defaults(func=cmd_export_tiledata)

    p = sub.add_parser("import-tiledata", help="read tile data into a tileset from a dump or Tilesets.rxdata")
    p.add_argument("tileset", help=".tsj file")
    p.add_argument("source", help=".json/.csv dump, or Tilesets.rxdata")
    p.add_argument("--tileset-id", type=int, default=None, help="RMXP tileset id (with Tilesets.rxdata)")
    p.set_defaults(func=cmd_import_tiledata)

    p = sub.add_parser("text", help="write every message of the compiled maps to a CSV")
    p.add_argument("--build", default=os.path.join(config.ROOT, "build"))
    p.add_argument("--out", default=os.path.join(config.ROOT, "build", "tiled_text.csv"))
    p.set_defaults(func=cmd_text)

    args = parser.parse_args(argv)
    if args.graphics:
        config.GRAPHICS = os.path.abspath(args.graphics)
    try:
        return args.func(config.Paths(args.src), args)
    except (TiledError, FileNotFoundError) as e:
        print("error: %s" % e, file=sys.stderr)
        return 1
