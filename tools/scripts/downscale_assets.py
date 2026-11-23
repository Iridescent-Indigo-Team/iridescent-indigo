#!/usr/bin/env python3
"""@package downscale_assets
One-time conversion of the sources to the game's 1x (256x192) scale.

Usage: python3 -I tools/scripts/downscale_assets.py [--check] [--force] [--jobs N]

Older versions of Pokessentials kept Essentials' 2x art in src/assets and
halved it on every build. Now src/assets holds the art at the size the game
shows it, which is easier to edit and share, and the build copies it as it is.
install_assets.sh halves new Essentials assets when it installs them; this
script converts what an older version installed or made:

  1. src/assets/graphics and src/assets/data, when they were installed by an
     older install_assets.sh (src/assets/.installed_manifest exists, but not
     src/assets/.asset_scale). Graphics are halved by resize_graphics.py
     (battle sprites become 96x96 frames), and the pixel values in the data
     by halve_data.rb. The 2x originals are kept in
     build/.downscale-backup/<date>/ until `make clean`. Installed files you
     haven't changed stay "installed" in the manifest, so install_assets.sh
     and uninstall_assets.sh keep working; files you changed stay yours.
  2. Localized graphics (src/assets/locales/<lang>/graphics) twice the size of
     the English graphic they replace.
  3. src/tiled, if its maps still use 32px tiles (tiled_compiler.py
     downscale; see tools/importer/tiled/tiledc/downscale.py). The autotile
     tilesets and event previews Tiled shows are then made again.

Each step is skipped when there's nothing to convert, so running the script
again is safe. --force runs step 1 on a src/assets/graphics that has no
install manifest (only do that if you know the art in it is 2x).

--check only tells whether step 1 is needed: it prints how to convert and
exits with status 1 if src/assets still holds 2x assets. `make` and
install_assets.sh run it first, so 1x and 2x files never get mixed.
"""

import argparse
import datetime
import hashlib
import os
import shutil
import subprocess
import sys

## Folder of this script.
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
## Root of the repository.
ROOT = os.path.normpath(os.path.join(SCRIPT_DIR, os.pardir, os.pardir))
## The asset sources.
ASSETS = os.path.join(ROOT, "src", "assets")
## Record of the files install_assets.sh installed: "<sha1>  <path>" lines.
MANIFEST = os.path.join(ASSETS, ".installed_manifest")
## Written by install_assets.sh and this script once src/assets is 1x.
SCALE_MARK = os.path.join(ASSETS, ".asset_scale")
## Graphics that weren't clean 2x upscales.
REPORT = os.path.join(ASSETS, ".resize_report.txt")
## Work folder (inside build/, so `make clean` removes it).
WORK = os.path.join(ROOT, "build", ".downscale")
## Where the 2x originals are moved.
BACKUP = os.path.join(ROOT, "build", ".downscale-backup")
## The Tiled sources.
TILED_SRC = os.path.join(ROOT, "src", "tiled")
## The Tiled tools.
TILED = os.path.join(ROOT, "tools", "importer", "tiled", "tiled_compiler.py")

## Message shown when src/assets still holds 2x assets.
OLD_SCALE_MESSAGE = """\
src/assets holds graphics and data installed at Essentials' 2x size by an
older version of Pokessentials. The sources are now kept at the game's 1x
size, and the build no longer halves them. Convert them once with:

    make downscale-assets

The 2x originals are kept in build/.downscale-backup/ until `make clean`.
See docs/BUILDING.md#source-scale."""


def assets_state():
    """The scale of src/assets: "1x", "2x" (installed by an older version) or
    None (nothing installed)."""
    if os.path.isfile(SCALE_MARK):
        return "1x"
    if os.path.isfile(MANIFEST) and os.path.getsize(MANIFEST) > 0:
        return "2x"
    return None


def sha1(path):
    """The SHA-1 of a file, as install_assets.sh records it."""
    h = hashlib.sha1()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def read_manifest():
    """@return list of [checksum, relative path] in file order"""
    entries = []
    if os.path.isfile(MANIFEST):
        with open(MANIFEST, encoding="utf-8") as f:
            for line in f.read().splitlines():
                if line:
                    entries.append([line[:40], line[42:]])
    return entries


def write_manifest(entries):
    """Writes the manifest, sorted by path like install_assets.sh does."""
    tmp = MANIFEST + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        for checksum, rel in sorted(entries, key=lambda e: e[1].encode("utf-8")):
            f.write("%s  %s\n" % (checksum, rel))
    os.replace(tmp, MANIFEST)


def run(args):
    """Runs a command, stopping the script if it fails."""
    proc = subprocess.run(args)
    if proc.returncode != 0:
        sys.exit("downscale_assets: %s failed (nothing in src/ was changed by this step)"
                 % os.path.basename(args[2] if args[1] == "-I" else args[1]))


def files_under(folder):
    """Relative paths of every file under folder (sorted)."""
    ret = []
    for base, dirs, files in os.walk(folder):
        dirs.sort()
        for name in sorted(files):
            ret.append(os.path.relpath(os.path.join(base, name), folder))
    return ret


def replace_files(converted, target, backup, log):
    """Moves every file of the converted folder over the same file in target,
    after moving the original into backup. @return number of files replaced"""
    count = 0
    for rel in files_under(converted):
        src = os.path.join(converted, rel)
        dst = os.path.join(target, rel)
        if os.path.isfile(dst):
            keep = os.path.join(backup, rel)
            os.makedirs(os.path.dirname(keep), exist_ok=True)
            shutil.move(dst, keep)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.move(src, dst)
        count += 1
    return count


def downscale_installed(args, stamp, log):
    """Step 1: halves src/assets/graphics and src/assets/data."""
    graphics = os.path.join(ASSETS, "graphics")
    data = os.path.join(ASSETS, "data")
    if os.path.isdir(WORK):
        shutil.rmtree(WORK)
    os.makedirs(WORK)
    # Convert everything first, so a failure leaves src/assets untouched.
    if os.path.isdir(graphics):
        log("Halving src/assets/graphics...")
        run([args.python, "-I", os.path.join(SCRIPT_DIR, "resize_graphics.py"), graphics,
             os.path.join(WORK, "graphics"), "--force", "--jobs", str(args.jobs), "--report", REPORT])
    if os.path.isdir(data):
        log("Halving the pixel values in src/assets/data...")
        run([args.ruby, os.path.join(SCRIPT_DIR, "halve_data.rb"), data, os.path.join(WORK, "data")])

    # Which installed files are unchanged since they were installed.
    entries = read_manifest()
    unchanged = set()
    for checksum, rel in entries:
        path = os.path.join(ASSETS, rel)
        if rel.startswith(("graphics/", "data/")) and os.path.isfile(path) and sha1(path) == checksum:
            unchanged.add(rel)

    backup = os.path.join(BACKUP, stamp)
    replaced = 0
    for name in ("graphics", "data"):
        if os.path.isdir(os.path.join(WORK, name)):
            replaced += replace_files(os.path.join(WORK, name), os.path.join(ASSETS, name),
                                      os.path.join(backup, name), log)
    shutil.rmtree(WORK, ignore_errors=True)

    # Installed files that were unchanged are still the installed ones (now
    # 1x); files changed by hand keep their old checksum, so they still count
    # as changed.
    for entry in entries:
        if entry[1] in unchanged:
            entry[0] = sha1(os.path.join(ASSETS, entry[1]))
    if entries:
        write_manifest(entries)
    with open(SCALE_MARK, "w", encoding="utf-8", newline="\n") as f:
        f.write("1x\n")
    log("Converted %d files in src/assets to 1x. The 2x originals are in %s (until `make clean`)."
        % (replaced, os.path.relpath(backup, ROOT)))
    if os.path.isfile(REPORT):
        with open(REPORT, encoding="utf-8") as f:
            lossy = sum(1 for line in f if line.strip() and not line.startswith("#"))
        if lossy:
            log("%d graphics weren't clean 2x upscales and lost detail; see %s."
                % (lossy, os.path.relpath(REPORT, ROOT)))


def png_size(path):
    """(width, height) of a PNG, or None."""
    with open(path, "rb") as f:
        head = f.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return int.from_bytes(head[16:20], "big"), int.from_bytes(head[20:24], "big")


def downscale_locales(args, stamp, log):
    """Step 2: halves localized graphics twice the size of the English ones."""
    locales = os.path.join(ASSETS, "locales")
    english = os.path.join(ASSETS, "graphics")
    if not os.path.isdir(locales) or not os.path.isdir(english):
        return
    sys.path.insert(0, SCRIPT_DIR)
    import resize_graphics
    from PIL import Image
    halved = 0
    for lang in sorted(os.listdir(locales)):
        folder = os.path.join(locales, lang, "graphics")
        if not os.path.isdir(folder):
            continue
        for rel in files_under(folder):
            if not rel.lower().endswith(".png"):
                continue
            path = os.path.join(folder, rel)
            ref = os.path.join(english, rel)
            size, ref_size = png_size(path), (png_size(ref) if os.path.isfile(ref) else None)
            if not size or not ref_size or size != (ref_size[0] * 2, ref_size[1] * 2):
                continue
            keep = os.path.join(BACKUP, stamp, "locales", lang, "graphics", rel)
            os.makedirs(os.path.dirname(keep), exist_ok=True)
            shutil.copy2(path, keep)
            with Image.open(path) as img:
                img.load()
                out = resize_graphics.halve(img)
            resize_graphics.save_png(out, path)
            halved += 1
    if halved:
        log("Halved %d localized graphics (they were twice the size of the English ones)." % halved)


def downscale_tiled(args, log):
    """Step 3: converts a 32px src/tiled to 16px tiles."""
    if not os.path.isfile(os.path.join(TILED_SRC, "maps", "registry.json")):
        return
    sys.path.insert(0, os.path.dirname(TILED))
    from tiledc.config import Paths
    from tiledc.downscale import downscale
    from tiledc.problems import TiledError
    try:
        converted = downscale(Paths(TILED_SRC), log=log)
    except TiledError as e:
        sys.exit("downscale_assets: %s" % e)
    if converted and os.path.isdir(os.path.join(ASSETS, "graphics")):
        # The autotile images and event previews Tiled shows (gitignored).
        run([args.python, "-I", TILED, "--ruby", args.ruby, "autotiles"])
        run([args.python, "-I", TILED, "--ruby", args.ruby, "previews"])


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0].split("\n", 1)[1])
    parser.add_argument("--check", action="store_true",
                        help="exit 1 (with instructions) if src/assets still holds 2x assets")
    parser.add_argument("--force", action="store_true",
                        help="halve src/assets/graphics and data even without an install manifest")
    parser.add_argument("--jobs", type=int, default=os.cpu_count() or 1)
    parser.add_argument("--python", default=sys.executable)
    parser.add_argument("--ruby", default=os.environ.get("RUBY", "ruby"))
    args = parser.parse_args(argv)

    def log(message):
        print(message, flush=True)

    state = assets_state()
    if args.check:
        if state == "2x":
            sys.stderr.write(OLD_SCALE_MESSAGE + "\n")
            return 1
        return 0

    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    if state == "2x" or (args.force and state != "1x"):
        downscale_installed(args, stamp, log)
    elif state == "1x":
        log("src/assets is already 1x.")
    elif os.path.isdir(os.path.join(ASSETS, "graphics")):
        log("src/assets/graphics wasn't installed by install_assets.sh, so its scale is unknown; it was left "
            "alone (use --force if it is 2x).")
    else:
        log("No assets installed in src/assets.")
    downscale_locales(args, stamp, log)
    downscale_tiled(args, log)
    return 0


if __name__ == "__main__":
    sys.exit(main())
