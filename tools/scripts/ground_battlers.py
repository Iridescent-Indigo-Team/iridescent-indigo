#!/usr/bin/env python3
"""@package ground_battlers
Stand every Pokémon's battle sprites on the ground by rewriting the y values
of their sprite metrics in src/pbs/pokemon_metrics.

Usage: python3 -I tools/scripts/ground_battlers.py [--graphics DIR] [--src DIR]
                                                   [--check] [--species IDS]
                                                   [--new-forms] [--keep-hover]
                                                   [--hover-min N] [--verbose]

Each battler sprite is shrunk to the 96x96 frames the game uses (exactly as
resize_graphics.py does for the build), and its feet are found: the lowest row
with an opaque pixel. Its y metric is then set so the feet stand on its side's
ground line:

  * FrontSprite y: the feet stand FOE_FEET_OFFSET below the foe's base
    position (where the faint animation crops the sprite).
  * BackSprite y: the feet stand PLAYER_FEET_OFFSET from the player's base
    position, above the message box, so full-body back sprites show their
    feet. A floating Pokémon (FrontSpriteAltitude > 0) is raised by its
    altitude on this side too. A cut-off back sprite (opaque pixels on its
    bottom row) has its cut edge put on the base position instead, which is
    hidden behind the message box.

The x offsets, altitude and shadow metrics are kept: they can't be worked out
from the sprites.

--keep-hover is a one-time migration for metrics that baked a floating
Pokémon's hover into its y value (as the Generation 9 Pack's do): a front
sprite with no FrontSpriteAltitude that its current y lifts at least
--hover-min pixels off the ground gets that lift as its FrontSpriteAltitude,
so it keeps floating, its shadow stays on the base, and its back sprite floats
too. Don't use it on metrics that are already grounded: a new sprite whose feet
sit higher in its frame would look like a hover. The same rules are used in the game by Debug > PBS editors >
Auto-set pokemon_metrics.txts (pbGroundedSpriteY); the offsets are copies of
Battle::Scene::PLAYER_FEET_OFFSET and FOE_FEET_OFFSET.

Graphics are read from src/assets/graphics (the installed source art), or
from lib/pokemon-essentials/Graphics if no art is installed. With --new-forms,
a form that has its own sprites and a different result from its species, but
no metrics entry yet, gets a new entry (added to the index next to its
species). With --check nothing is written, and the exit status is 1 if any
metric would change, so it can be used in CI.
"""

import argparse
import importlib.util
import os
import sys

try:
    from PIL import Image
except ImportError:  # pragma: no cover - reported to the user
    sys.stderr.write("ground_battlers.py needs Pillow: python3 -m pip install Pillow\n")
    sys.exit(2)

## Folder of this script.
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
## Root of the repository.
REPO_ROOT = os.path.normpath(os.path.join(SCRIPT_DIR, os.pardir, os.pardir))

sys.path.insert(0, os.path.join(REPO_ROOT, "tools", "importer", "pbs"))
from pbsjson.datasets import slug  # noqa: E402
from pbsjson.store import dumps, read_json, write_if_changed  # noqa: E402


def _load_resizer():
    """Loads resize_graphics.py, so sprites are shrunk exactly as the build does."""
    path = os.path.join(SCRIPT_DIR, "resize_graphics.py")
    spec = importlib.util.spec_from_file_location("resize_graphics", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


## The build's graphics resizer (resize_graphics.py).
resizer = _load_resizer()

## Copy of Battle::Scene::PLAYER_FEET_OFFSET (src/data/011_Battle/004_Scene/001_Battle_Scene.rb).
PLAYER_FEET_OFFSET = -12
## Copy of Battle::Scene::FOE_FEET_OFFSET.
FOE_FEET_OFFSET = 4
## Size of one battle sprite frame in the game.
FRAME = resizer.BATTLE_FRAME
## A back sprite whose bottom row has an unbroken run of at least this many
## opaque pixels is cut off rather than full-body. Feet touching the bottom of a
## big full-body sprite cover a few pixels at most (12 in the Gen 9 Pack art);
## a cut-off body covers many more (17 or more). Copy of
## CUT_OFF_SPRITE_RUN in the game.
CUT_OFF_RUN = 16
## Default for --hover-min: the smallest lift (in pixels) --keep-hover turns into an altitude.
HOVER_MIN = 6
## Folder of the metrics entries inside src/pbs.
METRICS_DIR = "pokemon_metrics"
## Folder of the form entries inside src/pbs.
FORMS_DIR = "pokemon_forms"
## Index file of a split dataset.
INDEX_FILE = "_index.json"
## The "$schema" value of a metrics entry file.
METRICS_SCHEMA = "../_schema/pokemon_metrics.entry.schema.json"


#===============================================================================
# Measuring sprites
#===============================================================================
class Feet:
    """Where a sprite's feet are within its 96x96 frame."""

    def __init__(self, gap, cropped):
        ## Transparent rows below the lowest opaque row (0 to FRAME - 1).
        self.gap = gap
        ## True if the sprite is cut off at the bottom of the frame (see CUT_OFF_RUN).
        self.cropped = cropped


def measure(path, rel):
    """Measures the feet of a battler sprite file.

    The sprite is shrunk into 96x96 frames like the build does. For a strip of
    animation frames the lowest feet of all frames are used, so no frame sinks
    below the ground.
    @param path absolute path of the PNG
    @param rel path relative to the graphics folder (for messages)
    @return a Feet, or None if the sprite is fully transparent
    """
    with Image.open(path) as img:
        img.load()
        frames = resizer.make_battle_sprite(img, rel)
    lowest = None
    cropped = False
    for i in range(frames.width // FRAME):
        alpha = frames.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME)).getchannel("A")
        bbox = alpha.getbbox()
        if bbox and (lowest is None or bbox[3] > lowest):
            lowest = bbox[3]
        cropped = cropped or bottom_run(alpha) >= CUT_OFF_RUN
    if lowest is None:
        return None
    return Feet(FRAME - lowest, cropped)


def bottom_run(alpha):
    """The longest unbroken run of opaque pixels along the bottom row of a frame.

    @param alpha the frame's alpha channel (an "L" image)
    @return int
    """
    best = run = 0
    for x in range(alpha.width):
        run = run + 1 if alpha.getpixel((x, alpha.height - 1)) > 0 else 0
        best = max(best, run)
    return best


def back_y(feet, altitude=0):
    """The BackSprite y that stands these feet on the player's ground line.

    Matches pbGroundedSpriteY in the game.
    @param feet a Feet
    @param altitude the entry's FrontSpriteAltitude
    @return int
    """
    if feet.cropped:
        return 0
    return feet.gap + PLAYER_FEET_OFFSET - altitude


def front_y(feet):
    """The FrontSprite y that stands these feet on the foe's ground line.

    @param feet a Feet
    @return int
    """
    return feet.gap + FOE_FEET_OFFSET


#===============================================================================
# Finding sprites
#===============================================================================
class SpriteFinder:
    """Finds battler sprites the way GameData::Species does (by species and form)."""

    def __init__(self, graphics_dir):
        ## The graphics folder (with a Pokemon subfolder).
        self.graphics_dir = graphics_dir
        ## Cache of measured sprites: path -> Feet or None.
        self.cache = {}
        ## Case-insensitive lookup of each sprite folder: folder -> {lower name: real name}.
        self.names = {}

    def _names(self, folder):
        if folder not in self.names:
            path = os.path.join(self.graphics_dir, "Pokemon", folder)
            files = os.listdir(path) if os.path.isdir(path) else []
            self.names[folder] = {f.lower(): f for f in files if f.lower().endswith(".png")}
        return self.names[folder]

    def file(self, folder, species, form, own_only=False):
        """The sprite file of a species/form in Pokemon/<folder>.

        Like the game, a form without its own sprite uses the species' sprite.
        @param folder "Front" or "Back"
        @param species species id, e.g. "PIKACHU"
        @param form form number (0 for the base form)
        @param own_only if True, only a sprite made for this form counts
        @return relative path inside the graphics folder, or None
        """
        names = self._names(folder)
        tries = ["%s_%d.png" % (species, form)] if form > 0 else []
        if not own_only or form == 0:
            tries.append("%s.png" % species)
        for name in tries:
            real = names.get(name.lower())
            if real:
                return os.path.join("Pokemon", folder, real)
        return None

    def feet(self, rel):
        """Measures a sprite file (cached). @return a Feet or None"""
        if rel not in self.cache:
            self.cache[rel] = measure(os.path.join(self.graphics_dir, rel), rel)
        return self.cache[rel]


#===============================================================================
# Metrics entries
#===============================================================================
class MetricsSet:
    """The pokemon_metrics entries in src/pbs and their index."""

    def __init__(self, src_dir):
        ## The src/pbs folder.
        self.src_dir = src_dir
        ## Folder of the entry files.
        self.dir = os.path.join(src_dir, METRICS_DIR)
        ## The index (which PBS file each entry goes in, and in what order).
        self.index = read_json(os.path.join(self.dir, INDEX_FILE))
        ## Entries by file stem.
        self.entries = {}
        ## Stems whose entries are new or changed.
        self.dirty = set()
        ## Whether the index changed.
        self.index_dirty = False
        for group in self.index["files"]:
            for stem in group["entries"]:
                self.entries[stem] = read_json(os.path.join(self.dir, stem + ".json"))

    @staticmethod
    def stem(species, form):
        """The file stem of an entry, named like the PBS importer does."""
        return slug("%s,%d" % (species, form) if form > 0 else species)

    def get(self, species, form):
        return self.entries.get(self.stem(species, form))

    def add_form(self, base_entry, form):
        """Adds a form entry copying its species' metrics, next to the species in the index.

        @return the new entry
        """
        species = base_entry["species"]
        entry = {"$schema": METRICS_SCHEMA, "species": species, "form": form}
        for key, value in base_entry.items():
            if key not in entry:
                entry[key] = dict(value) if isinstance(value, dict) else value
        stem = self.stem(species, form)
        self.entries[stem] = entry
        self.dirty.add(stem)
        base_stem = self.stem(species, 0)
        for group in self.index["files"]:
            names = group["entries"]
            if base_stem in names:
                # After the species and any of its forms with a lower number.
                pos = names.index(base_stem) + 1
                while pos < len(names):
                    other = self.entries.get(names[pos], {})
                    if other.get("species") != species or other.get("form", 0) > form:
                        break
                    pos += 1
                names.insert(pos, stem)
                self.index_dirty = True
                return entry
        raise KeyError("%s has no metrics entry to add form %d next to" % (species, form))

    def set_y(self, stem, key, value):
        """Sets back_sprite or front_sprite y of an entry. @return the old y"""
        entry = self.entries[stem]
        pos = entry.get(key)
        old = pos["y"] if pos else 0
        if old != value:
            if pos is None:
                entry[key] = {"x": 0, "y": value}
                # Keep the key order of the schema: back, front, then the rest.
                order = ["$schema", "species", "form", "back_sprite", "front_sprite"]
                ordered = {k: entry[k] for k in order if k in entry}
                ordered.update({k: v for k, v in entry.items() if k not in ordered})
                self.entries[stem] = ordered
            else:
                pos["y"] = value
            self.dirty.add(stem)
        return old

    def set_altitude(self, stem, value):
        """Sets front_sprite_altitude of an entry (placed after front_sprite)."""
        entry = self.entries[stem]
        if entry.get("front_sprite_altitude", 0) == value:
            return
        ordered = {}
        for key, val in entry.items():
            if key != "front_sprite_altitude":
                ordered[key] = val
            if key == "front_sprite":
                ordered["front_sprite_altitude"] = value
        if "front_sprite_altitude" not in ordered:
            ordered["front_sprite_altitude"] = value
        self.entries[stem] = ordered
        self.dirty.add(stem)

    def save(self):
        """Writes the changed entries and index. @return number of files written"""
        written = 0
        for stem in sorted(self.dirty):
            text = dumps(self.entries[stem]) + "\n"
            written += write_if_changed(os.path.join(self.dir, stem + ".json"), text)
        if self.index_dirty:
            written += write_if_changed(os.path.join(self.dir, INDEX_FILE), dumps(self.index) + "\n")
        return written


def form_numbers(src_dir):
    """Forms defined in src/pbs/pokemon_forms. @return {species: set of form numbers}"""
    ret = {}
    folder = os.path.join(src_dir, FORMS_DIR)
    if not os.path.isdir(folder):
        return ret
    index = read_json(os.path.join(folder, INDEX_FILE))
    for group in index["files"]:
        for stem in group["entries"]:
            entry = read_json(os.path.join(folder, stem + ".json"))
            ret.setdefault(entry["species"], set()).add(entry["form"])
    return ret


#===============================================================================
# Main
#===============================================================================
def default_graphics_dir():
    """src/assets/graphics if art is installed, otherwise the vendored Essentials art."""
    installed = os.path.join(REPO_ROOT, "src", "assets", "graphics")
    if os.path.isdir(os.path.join(installed, "Pokemon")):
        return installed
    return os.path.join(REPO_ROOT, "lib", "pokemon-essentials", "Graphics")


def ground(metrics, finder, species_filter=None, new_forms=False, forms=None,
           hover_min=None):
    """Works out new y metrics for every entry.

    @param hover_min with --keep-hover, the smallest lift turned into a
      FrontSpriteAltitude; None to keep no lifts
    @return (changes, missing): changes is a list of (stem, key, old, new)
      tuples (old and new are None for a new entry) and missing lists entries
      without sprites
    """
    changes = []
    missing = []
    targets = [(e["species"], e.get("form", 0)) for e in list(metrics.entries.values())]
    if new_forms and forms:
        for species, numbers in sorted(forms.items()):
            for form in sorted(numbers):
                if metrics.get(species, form) is None and metrics.get(species, 0) is not None:
                    targets.append((species, form))
    for species, form in targets:
        if species_filter and species not in species_filter:
            continue
        entry = metrics.get(species, form)
        added = entry is None
        if added:
            # A form with no entry: add it only if it has its own sprite and
            # would stand differently from its species.
            base = metrics.get(species, 0)
            own = [finder.file(f, species, form, own_only=True) for f in ("Back", "Front")]
            if not any(own):
                continue
            new = _wanted(base, species, form, finder)
            if new == _wanted(base, species, 0, finder):
                continue
            entry = metrics.add_form(base, form)
            changes.append((metrics.stem(species, form), "(new entry)", None, None))
        stem = metrics.stem(species, form)
        back_file = finder.file("Back", species, form)
        front_file = finder.file("Front", species, form)
        if not back_file and not front_file:
            missing.append(stem)
            continue
        # A new form entry copies its species' (already grounded) metrics, so
        # it has no old lift of its own.
        if hover_min is not None and not added and front_file \
                and not entry.get("front_sprite_altitude", 0):
            feet = finder.feet(front_file)
            old = entry.get("front_sprite", {}).get("y", 0)
            lift = (front_y(feet) - old) if feet else 0
            if lift >= hover_min:
                metrics.set_altitude(stem, lift)
                entry = metrics.entries[stem]
                changes.append((stem, "front_sprite_altitude", 0, lift))
        wanted = _wanted(entry, species, form, finder)
        for key, value in zip(("back_sprite", "front_sprite"), wanted):
            if value is None:
                continue
            old = metrics.set_y(stem, key, value)
            if old != value:
                changes.append((stem, key, old, value))
    return changes, missing


def cut_off_back_sprites(finder):
    """Lists every back sprite that is cut off at the bottom, including female,
    Shadow and shiny variants (which use their species' metrics).

    @return sorted list of paths relative to the graphics folder
    """
    ret = []
    for folder in ("Back", "Back shiny"):
        for real in sorted(finder._names(folder).values()):
            rel = os.path.join("Pokemon", folder, real)
            feet = finder.feet(rel)
            if feet and feet.cropped:
                ret.append(rel)
    return ret


def _wanted(entry, species, form, finder):
    """The (back y, front y) an entry should have; None where there's no sprite."""
    altitude = entry.get("front_sprite_altitude", 0) if entry else 0
    ret = []
    for folder, calc in (("Back", lambda f: back_y(f, altitude)), ("Front", front_y)):
        rel = finder.file(folder, species, form)
        feet = finder.feet(rel) if rel else None
        ret.append(calc(feet) if feet else None)
    return tuple(ret)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0].split("\n", 1)[1])
    parser.add_argument("--graphics", default=None,
                        help="graphics folder (default: src/assets/graphics, else lib/pokemon-essentials/Graphics)")
    parser.add_argument("--src", default=os.path.join(REPO_ROOT, "src", "pbs"),
                        help="the src/pbs folder")
    parser.add_argument("--check", action="store_true",
                        help="write nothing; exit 1 if any metric would change")
    parser.add_argument("--species", default=None,
                        help="only these species (comma-separated ids, e.g. PIKACHU,NIDORANfE)")
    parser.add_argument("--new-forms", action="store_true",
                        help="add entries for forms with their own sprites that need different metrics")
    parser.add_argument("--keep-hover", action="store_true",
                        help="one-time migration: turn lifts baked into front y values into FrontSpriteAltitude")
    parser.add_argument("--hover-min", type=int, default=HOVER_MIN,
                        help="with --keep-hover, the smallest lift (pixels) kept (default %(default)s)")
    parser.add_argument("--verbose", action="store_true", help="list every change")
    args = parser.parse_args(argv)

    graphics = args.graphics or default_graphics_dir()
    if not os.path.isdir(os.path.join(graphics, "Pokemon")):
        sys.stderr.write("No Pokemon sprites found in %s\n" % graphics)
        return 2
    metrics = MetricsSet(args.src)
    finder = SpriteFinder(graphics)
    species_filter = set(args.species.split(",")) if args.species else None
    forms = form_numbers(args.src) if args.new_forms else None
    try:
        hover_min = args.hover_min if args.keep_hover else None
        changes, missing = ground(metrics, finder, species_filter, args.new_forms, forms, hover_min)
        cropped = cut_off_back_sprites(finder) if not species_filter else []
    except ValueError as e:  # a sprite too big for a 96x96 frame
        sys.stderr.write("ERROR: %s\n" % e)
        return 1

    print("Sprites: %s" % os.path.relpath(graphics, REPO_ROOT))
    if args.verbose:
        for stem, key, old, new in changes:
            if old is None:
                print("  %s: %s" % (stem, key))
            else:
                print("  %s: %s %d -> %d" % (stem, key if key.endswith("altitude") else key + " y", old, new))
    entries = len({c[0] for c in changes})
    new_entries = sum(1 for c in changes if c[2] is None)
    changes = [c for c in changes if c[2] is not None]
    if cropped:
        print("%d back sprites are cut off at the bottom; replace them with full-body art."
              % len(cropped))
        print("(Their own species/form entries keep the cut edge behind the message box,")
        print("but female, Shadow and shiny variants use their species' metrics.)")
        for rel in cropped:
            print("  %s" % rel)
    if missing:
        print("%d entries have no sprites: %s" % (len(missing), ", ".join(missing)))
    if args.check:
        print("%d metrics in %d entries would change (%d new entries)" % (len(changes), entries, new_entries))
        return 1 if changes else 0
    written = metrics.save()
    print("%d metrics in %d entries changed (%d new entries); %d files written to %s"
          % (len(changes), entries, new_entries, written, os.path.relpath(metrics.dir, REPO_ROOT)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
