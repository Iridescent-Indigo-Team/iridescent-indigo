"""@package locjson.fonts
Glyph widths of the game's TrueType fonts, read straight from the .ttf files.

mkxp-z sizes fonts like Windows does: the size is the character cell height
(winAscent + winDescent), not the em size. font.cpp (calc_ppem_for_height)
turns the size into pixels per em, and glyph advances are the hmtx advances
scaled to that. The Power fonts are drawn on a 64-unit pixel grid, so at the
sizes MessageConfig uses (16/13/16) every advance is a whole number of pixels
and these widths are exact.
"""

import os
import struct


class FontError(Exception):
    """A font file is missing or isn't a TrueType font we can read."""


def _muldiv(a, b, c):
    """FreeType's FT_MulDiv: a * b / c rounded to the nearest integer."""
    if c == 0:
        return 0
    sign = -1 if (a < 0) ^ (b < 0) ^ (c < 0) else 1
    a, b, c = abs(a), abs(b), abs(c)
    return sign * ((a * b + c // 2) // c)


class TrueTypeFont:
    """The few tables of a .ttf file needed to measure text."""

    def __init__(self, path):
        ## Path of the font file.
        self.path = path
        try:
            with open(path, "rb") as f:
                data = f.read()
        except OSError as e:
            raise FontError("Can't read font %s: %s" % (path, e))
        tables = self._tables(data)
        for tag in ("head", "hhea", "hmtx", "cmap", "OS/2"):
            if tag not in tables:
                raise FontError("%s has no %s table." % (path, tag))
        head = tables["head"][0]
        ## Font units per em.
        self.units_per_em = struct.unpack(">H", data[head + 18:head + 20])[0]
        os2 = tables["OS/2"][0]
        win_ascent, win_descent = struct.unpack(">Hh", data[os2 + 74:os2 + 78])
        hhea = tables["hhea"][0]
        ascender, descender = struct.unpack(">hh", data[hhea + 4:hhea + 8])
        ## Units of the cell height (what the RGSS font size measures).
        self.cell_units = win_ascent + abs(win_descent) or (ascender - descender)
        num_metrics = struct.unpack(">H", data[hhea + 34:hhea + 36])[0]
        hmtx = tables["hmtx"][0]
        ## Advance width (font units) of each glyph id.
        self.advances = [struct.unpack(">H", data[hmtx + 4 * i:hmtx + 4 * i + 2])[0]
                         for i in range(num_metrics)]
        ## Codepoint -> glyph id.
        self.cmap = self._read_cmap(data, tables["cmap"][0])

    @staticmethod
    def _tables(data):
        if len(data) < 12:
            raise FontError("Not a font file.")
        count = struct.unpack(">H", data[4:6])[0]
        ret = {}
        for i in range(count):
            tag, _, offset, length = struct.unpack(">4sIII", data[12 + 16 * i:28 + 16 * i])
            ret[tag.decode("latin-1")] = (offset, length)
        return ret

    @staticmethod
    def _read_cmap(data, base):
        count = struct.unpack(">H", data[base + 2:base + 4])[0]
        best = None
        for i in range(count):
            platform, encoding, offset = struct.unpack(">HHI", data[base + 4 + 8 * i:base + 12 + 8 * i])
            fmt = struct.unpack(">H", data[base + offset:base + offset + 2])[0]
            if fmt == 12 and platform in (0, 3):
                best = (12, base + offset)
            elif fmt == 4 and platform in (0, 3) and (best is None or best[0] != 12):
                best = (4, base + offset)
        if best is None:
            raise FontError("No Unicode cmap.")
        fmt, off = best
        ret = {}
        if fmt == 4:
            segx2 = struct.unpack(">H", data[off + 6:off + 8])[0]
            segs = segx2 // 2
            ends = struct.unpack(">%dH" % segs, data[off + 14:off + 14 + segx2])
            starts_off = off + 16 + segx2
            starts = struct.unpack(">%dH" % segs, data[starts_off:starts_off + segx2])
            deltas = struct.unpack(">%dh" % segs, data[starts_off + segx2:starts_off + 2 * segx2])
            ranges_off = starts_off + 2 * segx2
            ranges = struct.unpack(">%dH" % segs, data[ranges_off:ranges_off + segx2])
            for s in range(segs):
                for cp in range(starts[s], ends[s] + 1):
                    if cp == 0xFFFF:
                        continue
                    if ranges[s] == 0:
                        gid = (cp + deltas[s]) & 0xFFFF
                    else:
                        addr = ranges_off + 2 * s + ranges[s] + 2 * (cp - starts[s])
                        gid = struct.unpack(">H", data[addr:addr + 2])[0]
                        if gid:
                            gid = (gid + deltas[s]) & 0xFFFF
                    if gid:
                        ret[cp] = gid
        else:
            groups = struct.unpack(">I", data[off + 12:off + 16])[0]
            for g in range(groups):
                s, e, gid = struct.unpack(">III", data[off + 16 + 12 * g:off + 28 + 12 * g])
                for cp in range(s, e + 1):
                    ret[cp] = gid + (cp - s)
        return ret

    def ppem(self, size):
        """Pixels per em for an RGSS font size (font.cpp calc_ppem_for_height)."""
        ppem = _muldiv(self.units_per_em, size, self.cell_units)
        if ppem > 1 and _muldiv(self.cell_units, ppem, self.units_per_em) > size:
            ppem -= 1
        return max(ppem, 1)


class Metrics:
    """Measures text in one font at one RGSS size."""

    def __init__(self, font, size):
        ## The TrueTypeFont.
        self.font = font
        ## The RGSS font size.
        self.size = size
        ppem = font.ppem(size)
        upem = font.units_per_em
        self._widths = {}
        for cp, gid in font.cmap.items():
            adv = font.advances[min(gid, len(font.advances) - 1)]
            self._widths[cp] = _muldiv(adv, ppem, upem)
        notdef = font.advances[0] if font.advances else 0
        ## Width of a character the font has no glyph for.
        self.missing_width = _muldiv(notdef, ppem, upem)

    def has_glyph(self, char):
        """True if the font can draw the character (control characters always can)."""
        return ord(char) < 32 or ord(char) in self._widths

    def char_width(self, char):
        """Width in pixels of one character (0 for wait characters)."""
        if char in ("\x01", "\x02", "\n"):
            return 0
        return self._widths.get(ord(char), self.missing_width)

    def width(self, text):
        """Width in pixels of a string, like Bitmap#text_size(text).width."""
        return sum(self.char_width(c) for c in text)


## Cache of loaded fonts by path.
_FONTS = {}


def load_metrics(fonts_dir, filename, size):
    """Metrics for a font file in fonts_dir at an RGSS size.

    @param fonts_dir folder of the .ttf files (src/assets/fonts)
    @param filename font file name, e.g. "power green.ttf"
    @param size RGSS font size
    """
    path = os.path.join(fonts_dir, filename)
    if path not in _FONTS:
        _FONTS[path] = TrueTypeFont(path)
    return Metrics(_FONTS[path], size)
