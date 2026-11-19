"""@package locjson.cli
Command line: update, validate and build.
"""

import argparse
import os
import re
import sys
from collections import defaultdict

from . import config as cfg
from .compile import write_language
from .csvio import CsvError, columns_for, read_csv, update_rows, write_csv
from .graphics import build_graphics, check_graphics
from .sources import gather, merge_duplicates, strings_from_event_csvs
from .validate import name_width_limits, validate_language

## How many warnings are printed per language without --verbose.
WARNING_LIMIT = 40


def _languages(config, codes):
    if not codes:
        return list(config.languages)
    ret = []
    for code in codes:
        lang = config.language(code)
        if lang is None:
            raise SystemExit("error: unknown language %s (known: %s)" % (
                code, ", ".join(l.code for l in config.languages)))
        ret.append(lang)
    return ret


def _gather(args):
    """@return (strings, events_loaded)"""
    return gather(pbs_dir=args.pbs, data_dir=args.data, build_dir=args.build_dir, events=not args.no_events)


def _is_event_file(file):
    return file.startswith("events/")


def cmd_update(config, args):
    """Writes the current English into every language's CSVs."""
    strings, events_loaded = _gather(args)
    by_file = defaultdict(list)
    for s in strings:
        by_file[s.file].append(s)
    for lang in _languages(config, args.lang):
        lang_dir = os.path.join(args.locales, lang.code)
        totals = defaultdict(int)
        changed = 0
        existing = set()
        if os.path.isdir(lang_dir):
            for folder, subdirs, files in os.walk(lang_dir):
                subdirs[:] = [d for d in subdirs if d != "graphics"]
                for name in files:
                    if name.lower().endswith(".csv"):
                        existing.add(os.path.relpath(os.path.join(folder, name), lang_dir).replace(os.sep, "/"))
        for file in sorted(set(by_file) | existing):
            if _is_event_file(file) and not events_loaded:
                continue   # without the maps, event CSVs are left as they are
            path = os.path.join(lang_dir, file)
            old_cols, old_rows = [], []
            if os.path.isfile(path):
                try:
                    old_cols, old_rows = read_csv(path)
                except CsvError as e:
                    print("error: %s (not updated)" % e, file=sys.stderr)
                    continue
            rows, stats = update_rows(old_rows, by_file.get(file, []))
            if file not in by_file and not rows:
                os.remove(path)
                changed += 1
                continue
            columns = columns_for(by_file.get(file, [])) if file in by_file else old_cols
            for col in old_cols:   # keep columns translators added
                if col and col not in columns:
                    columns.append(col)
            for k, v in stats.items():
                totals[k] += v
            if write_csv(path, columns, rows):
                changed += 1
        print("%s: %d files changed; %d new rows (%d filled from identical text), %d newly stale, "
              "%d newly obsolete." % (lang.code, changed, totals["new"], totals["reused"], totals["stale"],
                                      totals["obsolete"]))
    return 0


def _report(lang, problems, verbose):
    errors = [p for p in problems if not p.warning]
    warnings = [p for p in problems if p.warning]
    for p in errors:
        print("error: %s" % p, file=sys.stderr)
    shown = warnings if verbose else warnings[:WARNING_LIMIT]
    for p in shown:
        print("warning: %s" % p, file=sys.stderr)
    if len(shown) < len(warnings):
        print("... and %d more warnings for %s (--verbose shows all)" % (len(warnings) - len(shown), lang.code),
              file=sys.stderr)
    return errors, warnings


def _check_settings(config, langs):
    """Warns about languages missing from Settings::LANGUAGES."""
    path = os.path.join(cfg.ROOT, "src", "data", "001_Settings.rb")
    try:
        with open(path, "r", encoding="utf-8") as f:
            text = f.read()
    except OSError:
        return
    m = re.search(r"LANGUAGES\s*=\s*\[(.*?)\n\s*\]", text, re.S)
    block = m.group(1) if m else ""
    for lang in langs:
        if not re.search(r'^[^#\n]*"%s"' % re.escape(lang.code), block, re.M):
            print("warning: %s (%s) isn't in Settings::LANGUAGES in src/data/001_Settings.rb, so players "
                  "can't choose it" % (lang.code, lang.name), file=sys.stderr)


def _validate(config, args, langs):
    strings, events_loaded = _gather(args)
    widths = name_width_limits(strings, config, args.fonts)
    total = {}
    results = {}
    for lang in langs:
        lang_strings = strings
        if not events_loaded:
            lang_strings = strings + merge_duplicates(strings_from_event_csvs(os.path.join(args.locales, lang.code)))
        total_strings = len(lang_strings)
        problems, compiled = validate_language(config, lang, lang_strings, args.locales, args.fonts, widths)
        problems += check_graphics(config, lang, args.locales, args.graphics)
        errors, warnings = _report(lang, problems, args.verbose)
        done = len({(s.file, s.key) for s, _ in compiled})
        print("%s (%s): %d errors, %d warnings, %d of %d strings translated (%.1f%%)." % (
            lang.code, lang.name, len(errors), len(warnings), done, total_strings,
            100.0 * done / total_strings if total_strings else 100.0))
        total[lang.code] = (errors, warnings)
        results[lang.code] = compiled
    _check_settings(config, langs)
    failed = any(e for e, _ in total.values()) or (args.strict and any(w for _, w in total.values()))
    return failed, results


def cmd_validate(config, args):
    failed, _ = _validate(config, args, _languages(config, args.lang))
    if failed:
        print("Translations have %s; see above." % ("problems (STRICT)" if args.strict else "errors"),
              file=sys.stderr)
    return 1 if failed else 0


def cmd_build(config, args):
    """Validates, then writes the message files and graphics into the build folder."""
    langs = _languages(config, args.lang)
    failed, results = _validate(config, args, langs)
    if failed:
        print("Not building the translations; fix the errors above%s." % (
            " (STRICT=1 also stops on warnings)" if args.strict else ""), file=sys.stderr)
        return 1
    data_dir = os.path.join(args.out, "Data")
    for lang in langs:
        written = write_language(lang, results[lang.code], data_dir)
        count = build_graphics(lang, args.locales, args.out)
        print("%s: %s; %d localized graphics." % (
            lang.code, "wrote %d message files" % len(written) if written else "message files up to date", count))
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(prog="locales.py", description="CSV localization for Pokessentials.")
    parser.add_argument("--config", default=cfg.CONFIG_FILE, help="locales.json")
    parser.add_argument("--locales", default=cfg.LOCALES_DIR, help="folder of the language folders")
    parser.add_argument("--pbs", default=cfg.PBS_DIR, help="the JSON game data (src/pbs)")
    parser.add_argument("--data", default=None, help="RMXP data with the maps (default src/assets/data)")
    parser.add_argument("--build-dir", default=None, help="build folder to read compiled maps from")
    parser.add_argument("--graphics", default=cfg.GRAPHICS_DIR, help="English graphics")
    parser.add_argument("--fonts", default=cfg.FONTS_DIR, help="fonts folder")
    parser.add_argument("--no-events", action="store_true", help="leave event text out")
    parser.add_argument("--lang", action="append", help="only this language (repeatable)")
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("update", help="write the current English into the CSVs (keeps translations)")
    p.set_defaults(func=cmd_update)
    for name, func, text in (("validate", cmd_validate, "check the translations"),
                             ("build", cmd_build, "check, then compile into a build folder")):
        p = sub.add_parser(name, help=text)
        p.add_argument("--strict", action="store_true", help="fail on warnings too")
        p.add_argument("--verbose", action="store_true", help="print every warning")
        if name == "build":
            p.add_argument("out", help="the game folder (build/)")
        p.set_defaults(func=func)
    args = parser.parse_args(argv)
    if args.build_dir is None:
        args.build_dir = os.path.join(cfg.ROOT, "build")
    if args.lang:
        args.lang = [c for item in args.lang for c in item.split(",") if c]
    try:
        config = cfg.Config(args.config)
        return args.func(config, args)
    except (OSError, RuntimeError, CsvError) as e:
        print("error: %s" % e, file=sys.stderr)
        return 1
