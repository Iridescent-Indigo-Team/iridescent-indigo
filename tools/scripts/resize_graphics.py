#!/usr/bin/env python3
"""Halve Essentials graphics for the 256x192 build.

Usage: python3 -I tools/scripts/resize_graphics.py SRC_DIR OUT_DIR [--jobs N]
                                                   [--report FILE] [--force]

Every PNG under SRC_DIR is halved with nearest-neighbour sampling and written
to the same relative path under OUT_DIR. Nearest-neighbour keeps every pixel
a single uniform size (no "mixels") and never invents new colours.

Most Essentials art is a clean 2x upscale, so halving it loses nothing. Files
that are not (tilesets, fogs, some animations and UI) still get halved, but
they are listed in the report so they can be redrawn later.

Battle sprites always come out as 96x96 frames:
  * Pokemon/Front*, Pokemon/Back*  (battlers, all forms)
  * Pokemon/Eggs/* except icons    (egg battler and hatching sheet)
  * Trainers/*                     (front sprites and back-sprite sheets)
Each square frame (frame size = image height) is halved and then padded with
transparency at bottom-centre, which matches how Essentials anchors battlers
(ox = width / 2, oy = height). A frame that would still be bigger than 96x96
must lose only transparent margin, otherwise the build fails.

Files that are not PNGs are copied unchanged. Work is incremental: a file is
only processed again when its source is newer than its output (or --force).
"""

import argparse
import os
import shutil
import sys
from concurrent.futures import ProcessPoolExecutor

try:
    from PIL import Image
except ImportError:  # pragma: no cover - reported to the user
    sys.stderr.write("resize_graphics.py needs Pillow: python3 -m pip install Pillow\n")
    sys.exit(2)

BATTLE_FRAME = 96


def norm(rel):
    """Return a lower-case, forward-slash relative path for rule matching."""
    return rel.replace(os.sep, "/").lower()


def is_battle_sprite(rel):
    """True if the file is a battle sprite that must end up with 96x96 frames."""
    path = norm(rel)
    name = os.path.basename(path)
    if path.startswith("pokemon/front") or path.startswith("pokemon/back"):
        return True
    if path.startswith("pokemon/eggs/"):
        return "_icon" not in name
    if path.startswith("trainers/"):
        return True
    return False


def blank_transparent(img):
    """Return an RGBA copy where fully transparent pixels are (0, 0, 0, 0).

    Pixels with zero alpha can hold any colour, which would make clean art look
    lossy when comparing; this normalises them first.
    """
    rgba = img.convert("RGBA")
    alpha = rgba.getchannel("A")
    black = Image.new("RGBA", rgba.size, (0, 0, 0, 0))
    black.paste(rgba, (0, 0), alpha.point(lambda a: 255 if a > 0 else 0))
    return black


def is_clean_2x(img):
    """True if halving then doubling with nearest-neighbour gives img back."""
    w, h = img.size
    if w % 2 or h % 2:
        return False
    rgba = blank_transparent(img)
    small = rgba.resize((w // 2, h // 2), Image.NEAREST)
    return small.resize((w, h), Image.NEAREST).tobytes() == rgba.tobytes()


def pad_to_even(img):
    """Pad img on the right/bottom with transparency so both sides are even."""
    w, h = img.size
    if w % 2 == 0 and h % 2 == 0:
        return img
    out = Image.new("RGBA", (w + w % 2, h + h % 2), (0, 0, 0, 0))
    out.paste(img.convert("RGBA"), (0, 0))
    return out


def halve(img):
    """Halve img with nearest-neighbour, keeping palette images as palettes."""
    img = pad_to_even(img)
    w, h = img.size
    return img.resize((w // 2, h // 2), Image.NEAREST)


def fit_frame(frame, rel):
    """Pad or trim one halved battle frame to 96x96, anchored bottom-centre."""
    fw, fh = frame.size
    out = Image.new("RGBA", (BATTLE_FRAME, BATTLE_FRAME), (0, 0, 0, 0))
    # Offsets of the frame inside the 96x96 canvas (negative = frame bigger).
    dx = (BATTLE_FRAME - fw) // 2
    dy = BATTLE_FRAME - fh
    if dx < 0 or dy < 0:
        # Only allowed if everything that falls outside is transparent.
        box = (max(0, -dx), max(0, -dy), max(0, -dx) + BATTLE_FRAME, max(0, -dy) + BATTLE_FRAME)
        bbox = frame.getchannel("A").getbbox()
        if bbox and (bbox[0] < box[0] or bbox[1] < box[1] or bbox[2] > box[2] or bbox[3] > box[3]):
            raise ValueError(
                "%s: a %dx%d frame has opaque pixels outside the 96x96 battle area"
                % (rel, fw, fh))
        frame = frame.crop(box)
        dx = max(dx, 0)
        dy = max(dy, 0)
    out.paste(frame, (dx, dy))
    return out


def make_battle_sprite(img, rel):
    """Halve a battle sprite (or a horizontal strip of square frames) into 96x96 frames."""
    w, h = img.size
    if h == 0 or w % h != 0:
        raise ValueError("%s: %dx%d is not a strip of square frames" % (rel, w, h))
    count = w // h
    rgba = img.convert("RGBA")
    out = Image.new("RGBA", (BATTLE_FRAME * count, BATTLE_FRAME), (0, 0, 0, 0))
    for i in range(count):
        frame = rgba.crop((i * h, 0, (i + 1) * h, h))
        out.paste(fit_frame(halve(frame), rel), (i * BATTLE_FRAME, 0))
    return out


def save_png(img, dst):
    """Save img as PNG, keeping palette transparency information."""
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    tmp = dst + ".tmp"
    kwargs = {}
    if "transparency" in img.info:
        kwargs["transparency"] = img.info["transparency"]
    img.save(tmp, "PNG", optimize=False, **kwargs)
    os.replace(tmp, dst)


def process(job):
    """Process one file. Returns (rel, status, message)."""
    src, dst, rel = job
    if not rel.lower().endswith(".png"):
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(src, dst)  # new mtime, so the file counts as up to date
        return (rel, "copied", "")
    try:
        with Image.open(src) as img:
            img.load()
            clean = is_clean_2x(img)
            size = img.size
            if is_battle_sprite(rel):
                out = make_battle_sprite(img, rel)
            else:
                out = halve(img)
        save_png(out, dst)
    except Exception as e:  # report every failure, keep going
        return (rel, "error", str(e))
    if not clean:
        return (rel, "lossy", "%dx%d is not a clean 2x upscale" % size)
    return (rel, "ok", "")


def collect(src_root, out_root, force):
    """Yield (src, dst, rel) for every file that needs (re)processing."""
    stamp = os.path.getmtime(os.path.abspath(__file__))
    for dirpath, dirnames, filenames in os.walk(src_root):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
        for name in sorted(filenames):
            if name.startswith("."):
                continue
            src = os.path.join(dirpath, name)
            rel = os.path.relpath(src, src_root)
            dst = os.path.join(out_root, rel)
            if not force and os.path.exists(dst):
                dst_time = os.path.getmtime(dst)
                if dst_time >= os.path.getmtime(src) and dst_time >= stamp:
                    continue
            yield (src, dst, rel)


def remove_stale(src_root, out_root):
    """Delete outputs whose source file no longer exists."""
    removed = 0
    for dirpath, _, filenames in os.walk(out_root):
        for name in filenames:
            dst = os.path.join(dirpath, name)
            rel = os.path.relpath(dst, out_root)
            if not os.path.exists(os.path.join(src_root, rel)):
                os.remove(dst)
                removed += 1
    return removed


def update_report(path, results):
    """Merge this run's results into the persistent lossy-file report."""
    lossy = {}
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            for line in f:
                if line.startswith("#") or "\t" not in line:
                    continue
                rel, msg = line.rstrip("\n").split("\t", 1)
                lossy[rel] = msg
    for rel, status, msg in results:
        lossy.pop(rel, None)
        if status == "lossy":
            lossy[rel] = msg
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write("# Graphics that are not clean 2x upscales.\n")
        f.write("# They were halved with nearest-neighbour and lost detail;\n")
        f.write("# redraw them at 1x in src/assets/graphics to fix.\n")
        for rel in sorted(lossy):
            f.write("%s\t%s\n" % (rel, lossy[rel]))
    return len(lossy)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("src")
    parser.add_argument("out")
    parser.add_argument("--jobs", type=int, default=os.cpu_count() or 1)
    parser.add_argument("--report", default=None)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    if not os.path.isdir(args.src):
        sys.stderr.write("No graphics found in %s (run tools/scripts/install_assets.sh)\n" % args.src)
        os.makedirs(args.out, exist_ok=True)
        return 0
    os.makedirs(args.out, exist_ok=True)
    removed = remove_stale(args.src, args.out)
    jobs = list(collect(args.src, args.out, args.force))
    results = []
    if jobs:
        with ProcessPoolExecutor(max_workers=max(1, args.jobs)) as pool:
            results = list(pool.map(process, jobs, chunksize=16))
    errors = [r for r in results if r[1] == "error"]
    report = args.report or os.path.join(args.out, os.pardir, "resize_report.txt")
    lossy_total = update_report(report, results)
    print("Graphics: %d processed, %d removed, %d lossy in total (see %s), %d errors"
          % (len(results), removed, lossy_total, os.path.normpath(report), len(errors)))
    for rel, _, msg in errors:
        sys.stderr.write("ERROR: %s\n" % msg if msg.startswith(rel) else "ERROR: %s: %s\n" % (rel, msg))
    if errors:
        # Remove failed outputs so the next run retries them.
        for rel, _, _ in errors:
            dst = os.path.join(args.out, rel)
            if os.path.exists(dst):
                os.remove(dst)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
