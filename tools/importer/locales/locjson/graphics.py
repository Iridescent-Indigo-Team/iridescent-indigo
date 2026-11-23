"""@package locjson.graphics
Localized graphics: art with text drawn into it, redrawn per language.

src/assets/locales/<lang>/graphics/ mirrors src/assets/graphics/ and holds only
the files that differ (e.g. de/graphics/UI/Battle/cursor_command.png), at the
same 1x size as the English ones. The build copies them into
build/Graphics/Locales/<lang>/
and writes build/Data/graphics_<lang>.dat, a Marshal'd Hash from the English
path (lower case, no extension) to the localized one, so the game never scans
folders (001a_LocalizedGraphics.rb).
"""

import json
import os
import struct
import subprocess
import sys

from .validate import Problem

## Image formats the game loads (pbResolveBitmap).
IMAGE_EXTS = (".png", ".gif")


def image_size(path):
    """(width, height) of a PNG or GIF, or None."""
    try:
        with open(path, "rb") as f:
            head = f.read(32)
    except OSError:
        return None
    if head[:8] == b"\x89PNG\r\n\x1a\n" and head[12:16] == b"IHDR":
        return struct.unpack(">II", head[16:24])
    if head[:6] in (b"GIF87a", b"GIF89a"):
        return struct.unpack("<HH", head[6:10])
    return None


def _index_dir(folder):
    """Lower-case path without extension -> real relative path, for images under folder."""
    ret = {}
    if not os.path.isdir(folder):
        return ret
    for base, subdirs, files in os.walk(folder):
        subdirs.sort()
        for name in sorted(files):
            rel = os.path.relpath(os.path.join(base, name), folder).replace(os.sep, "/")
            stem, ext = os.path.splitext(rel)
            if ext.lower() in IMAGE_EXTS:
                ret.setdefault(stem.lower(), rel)
    return ret


def lang_graphics_dir(locales_dir, code):
    return os.path.join(locales_dir, code, "graphics")


def check_graphics(config, lang, locales_dir, graphics_dir):
    """Checks a language's graphics against the English ones. @return list of Problem"""
    problems = []
    folder = lang_graphics_dir(locales_dir, lang.code)
    english = _index_dir(graphics_dir)
    have = {}
    if os.path.isdir(folder):
        for base, subdirs, files in os.walk(folder):
            subdirs.sort()
            for name in sorted(files):
                full = os.path.join(base, name)
                rel = os.path.relpath(full, folder).replace(os.sep, "/")
                shown = "%s/graphics/%s" % (lang.code, rel)
                stem, ext = os.path.splitext(rel)
                if name.startswith("."):
                    continue
                if ext.lower() not in IMAGE_EXTS:
                    problems.append(Problem(shown, 0, "", "not a PNG or GIF; the game can't load it"))
                    continue
                if image_size(full) is None:
                    problems.append(Problem(shown, 0, "", "not a valid %s file" % ext[1:].upper()))
                    continue
                have[stem.lower()] = rel
                src = english.get(stem.lower())
                if src is None:
                    if english:
                        problems.append(Problem(shown, 0, "", "there is no English graphic "
                                                "src/assets/graphics/%s to replace (wrong name or folder?)" % rel,
                                                warning=True))
                    continue
                a = image_size(os.path.join(graphics_dir, src))
                b = image_size(full)
                if a and b and a != b and rel not in config.graphics_size_exceptions and \
                        "%s/%s" % (lang.code, rel) not in config.graphics_size_exceptions:
                    problems.append(Problem(shown, 0, "", "is %dx%d but the English graphic is %dx%d; the game "
                                            "expects the same size (allow it in locales.json "
                                            "graphics_size_exceptions)" % (b + a)))
    if english:
        missing = [p for p in config.graphics_with_text if p.lower() in english and p.lower() not in have]
        if missing:
            problems.append(Problem("%s/graphics" % lang.code, 0, "", "%d graphics with English text have no %s "
                                    "version yet: %s" % (len(missing), lang.name, ", ".join(missing)),
                                    warning=True))
    return problems


def build_graphics(lang, locales_dir, build_dir, python=sys.executable, ruby="ruby", jobs=None, log=print):
    """Copies a language's graphics into build/Graphics/Locales/<code> and writes its index."""
    from . import config as cfg
    folder = lang_graphics_dir(locales_dir, lang.code)
    out = os.path.join(build_dir, "Graphics", "Locales", lang.code)
    index_file = os.path.join(build_dir, "Data", "graphics_%s.dat" % lang.code)
    index = {}
    if os.path.isdir(folder):
        proc = subprocess.run([python, "-I", cfg.SYNC_DIR, folder, out, "--delete", "--quiet"])
        if proc.returncode != 0:
            raise RuntimeError("copying the %s graphics failed" % lang.code)
        for stem, rel in _index_dir(folder).items():
            index["graphics/" + stem] = "Graphics/Locales/%s/%s" % (lang.code, os.path.splitext(rel)[0])
    elif os.path.isdir(out):
        import shutil
        shutil.rmtree(out)
    os.makedirs(os.path.dirname(index_file), exist_ok=True)
    script = ("require 'json'; d = Marshal.dump(JSON.parse(STDIN.read)); "
              "File.binwrite(ARGV[0], d) if !File.file?(ARGV[0]) || File.binread(ARGV[0]) != d")
    proc = subprocess.run([ruby, "-e", script, index_file], input=json.dumps(index).encode("utf-8"))
    if proc.returncode != 0:
        raise RuntimeError("writing %s failed" % index_file)
    return len(index)
