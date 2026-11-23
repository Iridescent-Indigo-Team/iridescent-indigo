#!/usr/bin/env python3
"""Copy a folder into another, copying only files that changed.

Usage: python3 -I tools/scripts/sync_dir.py SRC DST [--delete] [--update]
                                            [--only PATTERN]... [--keep DIR]...
                                            [--skip-list FILE]

  --delete     remove files in DST that are not in SRC
  --update     never overwrite a file in DST that is newer than the one in SRC
               (keeps edits made by the in-game debug editors)
  --only       copy only file names matching this glob (can repeat)
  --keep       with --delete, never remove files under this folder of DST
               (relative to DST; can repeat), e.g. files other tools write
  --skip-list  skip files whose path relative to SRC matches a regular
               expression listed (one per line, whole path, any case) in FILE;
               a missing FILE skips nothing

Files named .gitkeep, desktop.ini, Thumbs.db and .DS_Store are ignored.
A file is copied when its size or modification time differs. This replaces
rsync so the build has no extra dependency.
"""

import argparse
import fnmatch
import os
import re
import shutil
import sys

IGNORED = {".gitkeep", "desktop.ini", "thumbs.db", ".ds_store"}


def wanted(name, only):
    """True if a file name should be synced."""
    if name.lower() in IGNORED:
        return False
    return not only or any(fnmatch.fnmatch(name, pattern) for pattern in only)


def read_skip_list(path):
    """Compiled patterns of a --skip-list file (none if it doesn't exist)."""
    if not path or not os.path.isfile(path):
        return []
    with open(path, encoding="utf-8") as f:
        return [re.compile(line, re.IGNORECASE) for line in f.read().splitlines() if line]


def sync(src, dst, delete, update, only, keep=(), skip=()):
    """Sync src into dst. Returns (copied, removed)."""
    copied = removed = 0
    seen = set()
    keep = [os.path.normcase(os.path.normpath(os.path.join(dst, k))) + os.sep for k in keep]
    for dirpath, dirnames, filenames in os.walk(src):
        dirnames.sort()
        rel_dir = os.path.relpath(dirpath, src)
        out_dir = os.path.normpath(os.path.join(dst, rel_dir))
        for name in sorted(filenames):
            if not wanted(name, only):
                continue
            rel = os.path.normpath(os.path.join(rel_dir, name)).replace(os.sep, "/")
            if any(p.fullmatch(rel) for p in skip):
                continue
            s = os.path.join(dirpath, name)
            d = os.path.join(out_dir, name)
            seen.add(os.path.normcase(os.path.normpath(d)))
            if os.path.exists(d):
                ss, ds = os.stat(s), os.stat(d)
                if ss.st_size == ds.st_size and int(ss.st_mtime) == int(ds.st_mtime):
                    continue
                if update and ds.st_mtime > ss.st_mtime:
                    continue
            os.makedirs(out_dir, exist_ok=True)
            shutil.copy2(s, d)
            copied += 1
    if delete and os.path.isdir(dst):
        for dirpath, dirnames, filenames in os.walk(dst, topdown=False):
            for name in filenames:
                d = os.path.join(dirpath, name)
                norm = os.path.normcase(os.path.normpath(d))
                if norm not in seen and not any(norm.startswith(k) for k in keep):
                    os.remove(d)
                    removed += 1
            kept_dir = any((os.path.normcase(os.path.normpath(dirpath)) + os.sep).startswith(k) for k in keep)
            if dirpath != dst and not kept_dir and not os.listdir(dirpath):
                os.rmdir(dirpath)
    return copied, removed


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("src")
    parser.add_argument("dst")
    parser.add_argument("--delete", action="store_true")
    parser.add_argument("--update", action="store_true")
    parser.add_argument("--only", action="append", default=[])
    parser.add_argument("--keep", action="append", default=[])
    parser.add_argument("--skip-list", default=None)
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()
    os.makedirs(args.dst, exist_ok=True)
    if not os.path.isdir(args.src):
        return 0
    copied, removed = sync(args.src, args.dst, args.delete, args.update, args.only, args.keep,
                           read_skip_list(args.skip_list))
    if not args.quiet and (copied or removed):
        print("%s: %d copied, %d removed" % (os.path.normpath(args.dst), copied, removed))
    return 0


if __name__ == "__main__":
    sys.exit(main())
