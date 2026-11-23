"""@package tests.test_locales
Tests of the CSV localization tools. Run with `make test-locales`.
"""

import json
import os
import shutil
import struct
import subprocess
import tempfile
import unittest
import zlib

from locjson import codes
from locjson import config as cfg
from locjson import messages as mt
from locjson.compile import write_language
from locjson.csvio import CsvError, Row, read_csv, render_csv, update_rows, write_csv
from locjson.fonts import load_metrics
from locjson.graphics import build_graphics, check_graphics
from locjson.sources import SourceString, merge_duplicates
from locjson.validate import validate_language

## Ruby, if installed.
RUBY = shutil.which("ruby")
## Essentials' sample RMXP data, if the submodule is checked out.
ESSENTIALS_DATA = os.path.join(cfg.ROOT, "lib", "pokemon-essentials", "Data")


class FixedMetrics:
    """Every character is 6 px wide (spaces too)."""

    def char_width(self, ch):
        return 0 if ch in ("\x01", "\x02", "\n") else 6

    def width(self, text):
        return sum(self.char_width(c) for c in text)


def png(path, width, height):
    """Writes a tiny transparent PNG."""
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + b"\x00\x00\x00\x00" * width for _ in range(height))
    data = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)) +
            chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)


#===============================================================================
class FontTest(unittest.TestCase):
    def test_power_green_sizes(self):
        m = load_metrics(cfg.FONTS_DIR, "power green.ttf", 16)
        # mkxp-z: size 16 is the cell height (1024 units of 768/em) -> 12 ppem
        self.assertEqual(m.font.ppem(16), 12)
        self.assertEqual(m.char_width("A"), 6)
        self.assertEqual(m.width("AA"), 12)
        self.assertTrue(m.has_glyph("ß"))
        self.assertTrue(m.has_glyph("¿"))
        small = load_metrics(cfg.FONTS_DIR, "power green small.ttf", 13)
        self.assertEqual(small.font.ppem(13), 9)


class StringToKeyTest(unittest.TestCase):
    def test_like_ruby(self):
        self.assertEqual(mt.string_to_key("Hello"), "Hello")
        self.assertEqual(mt.string_to_key("  Hello  there "), "Hello there")
        self.assertEqual(mt.string_to_key("a\n  b"), "a\nb")
        self.assertEqual(mt.string_to_key("a  \nb"), "a\nb")
        self.assertEqual(mt.string_to_key("a\tb"), "a\tb")


class CodesTest(unittest.TestCase):
    def kinds(self, text):
        return [(t.kind, t.name) for t in codes.tokenize(text) if t.kind != codes.TEXT]

    def test_codes(self):
        self.assertEqual(self.kinds(r"\bHi \PN! \v[3]\n\c[2]x\wt[5]\."),
                         [("code", "b"), ("code", "pn"), ("code", "v"), ("code", "n"), ("code", "c"),
                          ("code", "wt"), ("code", ".")])
        self.assertEqual(self.kinds(r"\n[2] and \[ff00ff00]"), [("code", "n"), ("code", "color")])
        bad = [t for t in codes.tokenize(r"Hi \PX!") if t.kind == codes.BAD]
        self.assertEqual(len(bad), 1)
        self.assertEqual([t.raw for t in codes.tokenize(r"a \\ b")], ["a \\ b"])

    def test_braces(self):
        toks = [t for t in codes.tokenize("{1} {2:d} {1|def.acc} {pg:er|sie} {1|plural:a|b} {x}")
                if t.kind != codes.TEXT]
        self.assertEqual([(t.kind, t.name, t.arg) for t in toks],
                         [("placeholder", "1", None), ("placeholder", "2", "d"), ("grammar", "1", "def.acc"),
                          ("grammar", "pg", "pg"), ("grammar", "1", "plural")])
        self.assertEqual(toks[3].options, ["er", "sie"])
        self.assertEqual([t.kind for t in codes.tokenize("{1|what is this}")], [codes.BAD])

    def test_displayed_text(self):
        s = codes.displayed_text(r"\bHi, \PN!\nOK&lt;3\1<b>x</b>", {"pn": "WWW"})
        self.assertEqual(s, "Hi, WWW!\nOK<3\x01x")


class WrapTest(unittest.TestCase):
    def test_message_wrap(self):
        m = FixedMetrics()
        # 10 chars = 60 px per line at width 61 ("x + 1 > width")
        lines, overflow = codes.message_lines("aaaa bbbb cccc dddd", m, 61)
        self.assertEqual((lines, overflow), (2, []))
        lines, overflow = codes.message_lines("aaaaaaaaaaaaaa", m, 61)
        self.assertEqual(overflow, ["aaaaaaaaaaaaaa"])
        self.assertEqual(codes.message_lines("a\nb\nc", m, 61)[0], 3)

    def test_chunk_wrap(self):
        m = FixedMetrics()
        self.assertEqual(codes.chunk_lines("aaaa bbbb cccc", m, 60)[0], 2)
        self.assertEqual(codes.chunk_lines("well-known thing", m, 42)[0], 3)
        self.assertEqual(codes.chunk_lines("aaaaaaaaaaaa", m, 60)[1], ["aaaaaaaaaaaa"])


class CsvTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.dir)

    def test_round_trip(self):
        path = os.path.join(self.dir, "a.csv")
        rows = [Row({"key": "k1", "english": 'Say "hi", then\nleave', "translation": 'Sag "hallo",\ndann geh'}),
                Row({"key": "k2", "english": "Plain", "translation": ""})]
        cols = ["key", "context", "english", "translation", "status", "notes"]
        self.assertTrue(write_csv(path, cols, rows))
        self.assertFalse(write_csv(path, cols, rows))
        with open(path, "rb") as f:
            self.assertTrue(f.read().startswith(b"\xef\xbb\xbf"))
        _, back = read_csv(path)
        self.assertEqual(back[0]["english"], 'Say "hi", then\nleave')
        self.assertEqual(back[0]["translation"], 'Sag "hallo",\ndann geh')
        self.assertEqual(back[1].line, 5)   # row 1 spans lines 2-4

    def test_crlf_and_errors(self):
        path = os.path.join(self.dir, "b.csv")
        with open(path, "wb") as f:
            f.write(b'key,english,translation\r\nk,"a\r\nb","x\r\ny"\r\n')
        _, rows = read_csv(path)
        self.assertEqual(rows[0]["translation"], "x\ny")
        with open(path, "wb") as f:
            f.write(b"key,english,translation\nk,a,b,c,d\n")
        with self.assertRaises(CsvError):
            read_csv(path)
        with open(path, "wb") as f:
            f.write(b"key,translation\n")
        with self.assertRaises(CsvError):
            read_csv(path)

    def test_update(self):
        old = [Row({"key": "a", "english": "Apple", "translation": "Apfel", "notes": "n"}),
               Row({"key": "b", "english": "Bee", "translation": "Biene"}),
               Row({"key": "gone", "english": "Old", "translation": "Alt"}),
               Row({"key": "gone2", "english": "Older", "translation": ""})]
        strings = [SourceString("x.csv", "a", "Apple", 1), SourceString("x.csv", "b", "Bees", 1),
                   SourceString("x.csv", "c", "Apple", 1), SourceString("x.csv", "d", "New", 1)]
        rows, stats = update_rows(old, strings)
        by = {r["key"]: r for r in rows}
        self.assertEqual(by["a"]["translation"], "Apfel")
        self.assertEqual(by["a"]["notes"], "n")
        self.assertEqual(by["b"]["status"], "stale")
        self.assertEqual(by["b"]["english"], "Bees")
        self.assertEqual(by["c"]["translation"], "Apfel")
        self.assertEqual(by["d"].get("translation", ""), "")
        self.assertEqual(by["gone"]["status"], "obsolete")
        self.assertNotIn("gone2", by)
        self.assertEqual(stats, {"new": 2, "stale": 1, "obsolete": 1, "reused": 1})

    def test_merge_duplicates(self):
        a = SourceString("x.csv", "A.category", "Seed", mt.SPECIES_CATEGORIES)
        b = SourceString("x.csv", "B.category", "Seed", mt.SPECIES_CATEGORIES)
        c = SourceString("x.csv", "C.category", "Mouse", mt.SPECIES_CATEGORIES)
        out = merge_duplicates([a, b, c])
        self.assertEqual([s.key for s in out], ["A.category", "C.category"])
        self.assertEqual(out[0].also, ["B.category"])


#===============================================================================
class ValidateTest(unittest.TestCase):
    """Validation and compilation of a small German translation."""

    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.locales = os.path.join(self.dir, "locales")
        self.config = cfg.Config()
        self.de = self.config.language("de")
        self.strings = [
            SourceString("items.csv", "POTION.name", "Potion", mt.ITEM_NAMES, noun="POTION", field="items.name"),
            SourceString("items.csv", "POTION.name_plural", "Potions", mt.ITEM_NAME_PLURALS, noun="POTION",
                         number="pl", field="items.name_plural"),
            SourceString("items.csv", "ANTIDOTE.name", "Antidote", mt.ITEM_NAMES, noun="ANTIDOTE",
                         field="items.name"),
            SourceString("scripts.csv", "s.1", "You got {1}!", mt.SCRIPT_TEXTS),
            SourceString("scripts.csv", "s.2", "{1} has {2:d} items.", mt.SCRIPT_TEXTS),
            SourceString("scripts.csv", "s.3", "Hello, \\PN! <b>Hi</b>", mt.SCRIPT_TEXTS),
            SourceString("scripts.csv", "s.4", "You have {1} {2}.", mt.SCRIPT_TEXTS),
            SourceString("events/map001.csv", "ev001.p1.c001", "\\bWelcome, \\PN!", mt.EVENT_TEXTS,
                         map_id=1, message=True),
            SourceString("events/map001.csv", "ev001.p1.c002", "Short.", mt.EVENT_TEXTS, map_id=1, message=True),
        ]

    def tearDown(self):
        shutil.rmtree(self.dir)

    def write(self, file, rows, noun=False):
        cols = ["key", "context", "english", "translation", "status", "notes"] + (["gender", "sound"] if noun else [])
        write_csv(os.path.join(self.locales, "de", file), cols, [Row(r) for r in rows])

    def eng(self, key):
        return next(s.english for s in self.strings if s.key == key)

    def row(self, key, translation, **kw):
        r = {"key": key, "english": self.eng(key), "translation": translation}
        r.update(kw)
        return r

    def run_validate(self):
        problems, compiled = validate_language(self.config, self.de, self.strings, self.locales, cfg.FONTS_DIR)
        errors = [str(p) for p in problems if not p.warning]
        warnings = [str(p) for p in problems if p.warning]
        return errors, warnings, compiled

    def write_good(self):
        self.write("items.csv", [self.row("POTION.name", "Trank", gender="m"),
                                 self.row("POTION.name_plural", "Tränke"),
                                 self.row("ANTIDOTE.name", "Gegengift", gender="n")], noun=True)
        self.write("scripts.csv", [self.row("s.1", "Du erhältst {1|def.acc}!"),
                                   self.row("s.2", "{1} hat {2:d} {2|plural:Item|Items}."),
                                   self.row("s.3", "Hallo, \\PN! <b>Hi</b>"),
                                   self.row("s.4", "Du hast {1} {2}.")])
        self.write("events/map001.csv", [self.row("ev001.p1.c001", "\\bWillkommen, \\PN! {pg:Er|Sie} ist da."),
                                         self.row("ev001.p1.c002", "")])

    def test_good(self):
        self.write_good()
        errors, warnings, compiled = self.run_validate()
        self.assertEqual(errors, [])
        self.assertTrue(any("1 rows in 1 files aren't translated" in w for w in warnings), warnings)
        self.assertEqual(len(compiled), 8)

    def test_errors(self):
        self.write_good()
        self.write("scripts.csv", [self.row("s.1", "Du erhältst {3}!"),
                                   self.row("s.2", "{1} hat {2:s} Items."),
                                   self.row("s.3", "Hallo, \\PM! <b>Hi \\qq"),
                                   self.row("s.4", "{1|def.xyz} {2|g:a}"),
                                   {"key": "s.unknown", "english": "x", "translation": "y"},
                                   self.row("s.4", "dup")])
        self.write("events/map001.csv", [self.row("ev001.p1.c001", "Willkommen! Ein€ " + "W" * 40),
                                         self.row("ev001.p1.c002", "Kurz.", status="maybe")])
        errors, warnings, _ = self.run_validate()
        text = "\n".join(errors)
        for expected in ("{3}: the English has no {3}", "{2:s}: the English formats {2} as {2:d}",
                         "control codes differ from the English: missing \\pn; extra \\pm",
                         "unknown control code \\qq", "has no article \"def.xyz\"",
                         "{2|g:a} needs a choice per gender",
                         "duplicate key", "can't draw '€'", "is wider than the message box",
                         "unknown status \"maybe\""):
            self.assertIn(expected, text)
        self.assertTrue(any("<b> is never closed" in e or "format codes" in w for e in errors for w in warnings))
        self.assertTrue(any("missing \\b" in w for w in warnings))
        self.assertTrue(any("this key isn't in the game" in w for w in warnings))

    def test_conflict_and_overflow_warning(self):
        self.strings.append(SourceString("events/map001.csv", "ev002.p1.c001", "Short.", mt.EVENT_TEXTS,
                                         map_id=1, message=True))
        self.strings[-2].also = []
        self.write_good()
        long_text = " ".join(["Wort"] * 40)
        self.write("events/map001.csv", [self.row("ev001.p1.c001", "\\bHallo \\PN " + long_text),
                                         self.row("ev001.p1.c002", "Kurz."),
                                         {"key": "ev002.p1.c001", "english": "Short.", "translation": "Knapp."}])
        errors, warnings, _ = self.run_validate()
        self.assertTrue(any("translated differently" in e for e in errors), errors)
        self.assertTrue(any("needs " in w and "the box shows 2" in w for w in warnings), warnings)

    @unittest.skipIf(not RUBY, "needs Ruby")
    def test_compile_and_runtime(self):
        self.write_good()
        _, _, compiled = self.run_validate()
        game = os.path.join(self.dir, "game")
        written = write_language(self.de, compiled, os.path.join(game, "Data"))
        self.assertEqual(len(written), 2)
        self.assertEqual(write_language(self.de, compiled, os.path.join(game, "Data")), [])
        exprs = [
            '_INTL("You got {1}!", "Trank")',
            '_INTL("You got {1}!", "Gegengift")',
            '_INTL("{1} has {2:d} items.", "Ash", 1)',
            '_ISPRINTF("{1} has {2:d} items.", "Ash", 3)',
            '_INTL("Unknown text {1}", "x")',
            '_MAPINTL(1, "\\\\bWelcome,  \\\\PN!")',
            '$player.female = true; _MAPINTL(1, "\\\\bWelcome, \\\\PN!")',
            '_INTL("{1|g:er|sie|es}", "Gegengift")',
            '1234567.to_s_formatted',
            'MessageTypes.getFromHash(MessageTypes::ITEM_NAME_PLURALS, "Potions")',
        ]
        proc = subprocess.run([RUBY, os.path.join(cfg.TOOL_DIR, "tests", "runtime_smoke.rb"), game, "de"],
                              input="\n".join(exprs).encode("utf-8"), stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE)
        self.assertEqual(proc.returncode, 0, proc.stderr.decode())
        out = [json.loads(line)[0] for line in proc.stdout.decode("utf-8").splitlines()]
        self.assertEqual(out, [
            "Du erhältst den Trank!",
            "Du erhältst das Gegengift!",
            "Ash hat {2:d} Item.",
            "Ash hat 3 Items.",
            "Unknown text x",
            "\\bWillkommen, \\PN! Er ist da.",
            "\\bWillkommen, \\PN! Sie ist da.",
            "es",
            "1.234.567",
            "Tränke",
        ])


class GrammarTablesTest(unittest.TestCase):
    """The article tables of every language, through the Ruby runtime."""

    @unittest.skipIf(not RUBY, "needs Ruby")
    def test_articles(self):
        config = cfg.Config()
        cases = {
            "fr": [("Potion", "f", "{1|def}", "la Potion"), ("Antidote", "m", "{1|def}", "l’Antidote"),
                   ("Rappel", "m", "{1|de.def}", "du Rappel"), ("Rappel", "m", "{1|A.def}", "Au Rappel")],
            "it": [("Spray", "m", "{1|def}", "lo Spray"), ("Pozione", "f", "{1|indef}", "una Pozione"),
                   ("Antidoto", "m", "{1|def}", "l’Antidoto"), ("Revitalizzante", "m", "{1|di.def}", "del Revitalizzante")],
            "es": [("Poción", "f", "{1|def}", "la Poción"), ("Antídoto", "m", "{1|de.def}", "del Antídoto")],
            "es_419": [("Poción", "f", "{1|indef}", "una Poción")],
            "de": [("Trank", "m", "{1|def.dat}", "dem Trank"), ("Beere", "f", "{1|Indef}", "Eine Beere")],
        }
        for code, items in cases.items():
            lang = config.language(code)
            tmp = tempfile.mkdtemp()
            try:
                compiled = []
                for n, (noun, gender, _, _) in enumerate(items):
                    s = SourceString("items.csv", "I%d.name" % n, "Item %d" % n, mt.ITEM_NAMES, noun="I%d" % n)
                    compiled.append((s, Row({"translation": noun, "gender": gender})))
                write_language(lang, compiled, os.path.join(tmp, "Data"))
                exprs = ['_INTL("%s", "%s")' % (tok, noun) for noun, _, tok, _ in items]
                proc = subprocess.run([RUBY, os.path.join(cfg.TOOL_DIR, "tests", "runtime_smoke.rb"), tmp, code],
                                      input="\n".join(exprs).encode("utf-8"), stdout=subprocess.PIPE)
                out = [json.loads(line)[0] for line in proc.stdout.decode("utf-8").splitlines()]
                self.assertEqual(out, [want for _, _, _, want in items], code)
            finally:
                shutil.rmtree(tmp)


#===============================================================================
class GraphicsTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.english = os.path.join(self.dir, "graphics")
        self.locales = os.path.join(self.dir, "locales")
        png(os.path.join(self.english, "UI", "Battle", "cursor_command.png"), 4, 2)
        png(os.path.join(self.english, "Titles", "start.png"), 4, 2)

    def tearDown(self):
        shutil.rmtree(self.dir)

    def test_checks(self):
        config = cfg.Config()
        config.graphics_with_text = ["UI/Battle/cursor_command", "Titles/start"]
        de = config.language("de")
        png(os.path.join(self.locales, "de", "graphics", "UI", "Battle", "cursor_command.png"), 4, 2)
        png(os.path.join(self.locales, "de", "graphics", "Titles", "Start.png"), 8, 2)
        png(os.path.join(self.locales, "de", "graphics", "UI", "typo.png"), 4, 2)
        problems = [str(p) for p in check_graphics(config, de, self.locales, self.english)]
        self.assertTrue(any("Start.png: is 8x2 but the English graphic is 4x2" in p for p in problems), problems)
        self.assertTrue(any("typo.png: there is no English graphic" in p for p in problems), problems)
        self.assertFalse(any("graphics with English text have no" in p for p in problems), problems)

    @unittest.skipIf(not RUBY, "needs Ruby")
    def test_index(self):
        de = cfg.Config().language("de")
        src = os.path.join(self.locales, "de", "graphics", "UI", "Battle", "cursor_command.png")
        png(src, 4, 2)
        build = os.path.join(self.dir, "build")
        self.assertEqual(build_graphics(de, self.locales, build, log=lambda *a: None), 1)
        out = os.path.join(build, "Graphics", "Locales", "de", "UI", "Battle", "cursor_command.png")
        # Copied as it is: localized graphics are already at the game's size.
        with open(src, "rb") as a, open(out, "rb") as b:
            self.assertEqual(a.read(), b.read())
        proc = subprocess.run([RUBY, "-e", "p Marshal.load(File.binread(ARGV[0]))",
                               os.path.join(build, "Data", "graphics_de.dat")], stdout=subprocess.PIPE)
        self.assertIn('"graphics/ui/battle/cursor_command"=>"Graphics/Locales/de/UI/Battle/cursor_command"',
                      proc.stdout.decode().replace(" => ", "=>"))


#===============================================================================
@unittest.skipIf(not RUBY, "needs Ruby")
class EventsTest(unittest.TestCase):
    def ruby(self, code):
        proc = subprocess.run([RUBY, "-r", cfg.EXTRACT_EVENTS, "-e", code], stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE)
        self.assertEqual(proc.returncode, 0, proc.stderr.decode())
        return json.loads(proc.stdout.decode("utf-8"))

    def test_show_text_fixes(self):
        # 6 lines are split into 4 + 2; a short first line gets the second
        # merged into it with \n; "\B " becomes "\b"
        out = self.ruby("""
          C = RPG::EventCommand
          list = [C.new(101, 0, ["\\\\B Hi"]), C.new(401, 0, ["there you are."]), C.new(401, 0, ["l3."]),
                  C.new(401, 0, ["l4."]), C.new(401, 0, ["l5."]), C.new(401, 0, ["l6."]), C.new(0, 0, [])]
          texts = []
          ExtractEvents.collect(ExtractEvents.fix_show_text(list), {}, texts)
          print JSON.generate(texts.map { |t| t["text"] })
        """)
        self.assertEqual(out, ["\\bHi\\nthere you are. l3. l4.", "l5.\\nl6."])

    @unittest.skipIf(not os.path.isfile(os.path.join(ESSENTIALS_DATA, "MapInfos.rxdata")),
                     "needs lib/pokemon-essentials")
    def test_essentials_maps(self):
        proc = subprocess.run([RUBY, cfg.EXTRACT_EVENTS, ESSENTIALS_DATA], stdout=subprocess.PIPE)
        doc = json.loads(proc.stdout.decode("utf-8"))
        self.assertGreater(len(doc["texts"]), 500)
        self.assertTrue(any(t["map"] == 0 for t in doc["texts"]))
        self.assertTrue(all(isinstance(t["text"], str) for t in doc["texts"]))


if __name__ == "__main__":
    unittest.main()
