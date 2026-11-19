"""Tests for the PBS <-> JSON converter.

Run with `make test-pbs`. The round-trip tests use the Essentials PBS files in
lib/pokemon-essentials/PBS.
"""

import json
import os
import re
import shutil
import tempfile
import unittest

from pbsjson.config import Config
from pbsjson.fields import Field
from pbsjson.pbs_text import (PbsError, csv_quote, csv_unquote, format_float, split_csv_line,
                              write_record)
from pbsjson.store import (STATE_FILE, export_pbs, load_json_tree, read_pbs_dir, render_pbs,
                           write_json_tree)
from pbsjson.validate import validate

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
ESSENTIALS_PBS = os.path.join(ROOT, "lib", "pokemon-essentials", "PBS")


def quiet(_message):
    pass


def normalized_lines(path):
    """A PBS file's lines without comments, blank lines and the BOM."""
    with open(path, encoding="utf-8-sig") as f:
        text = f.read()
    out = []
    for line in text.split("\n"):
        line = line.rstrip("\r")
        if line.startswith("#") or not line.strip():
            continue
        out.append(re.sub(r"\s*#.*$", "", line).rstrip())
    return out


class PbsTextTest(unittest.TestCase):
    """The ports of the compiler's CSV helpers."""

    def test_split_csv_line(self):
        self.assertEqual(split_csv_line("a, b ,c"), ["a", "b", "c"])
        self.assertEqual(split_csv_line('"Man, I lost!"'), ['"Man, I lost!"'])
        self.assertEqual(split_csv_line("1,,3"), ["1", "", "3"])

    def test_quote(self):
        self.assertEqual(csv_quote("Man, I lost!"), '"Man, I lost!"')
        self.assertEqual(csv_quote("plain"), "plain")
        self.assertEqual(csv_unquote('"Man, I lost!"'), "Man, I lost!")
        self.assertEqual(csv_unquote(csv_quote('say "hi", ok')), 'say "hi", ok')

    def test_format_float(self):
        self.assertEqual(format_float(0.7), "0.7")
        self.assertEqual(format_float(7.0), "7.0")
        self.assertEqual(format_float(1e16), "1.0e+16")
        self.assertEqual(format_float(1.5e-5), "1.5e-05")

    def test_write_record_trims_trailing_optionals(self):
        self.assertEqual(write_record([20, None, None, None, None, None], "uUUUUU"), "20")
        self.assertEqual(write_record([20, None, 5, None, None, None], "uUUUUU"), "20,,5")
        self.assertEqual(write_record([1, "TACKLE", 5, "GROWL"], "*ue"), "1,TACKLE,5,GROWL")
        self.assertEqual(write_record(["PIKACHU", None], "eV"), "PIKACHU")


class ConfigTest(unittest.TestCase):
    """names.json must name every multi-value field."""

    def test_missing_tuple_names_is_an_error(self):
        config = Config()
        entry = {"key": "BrandNewPair", "property": "brand_new_pair", "type": "uu"}
        with self.assertRaises(PbsError):
            Field(entry, "pokemon", config.names)

    def test_every_engine_field_is_named(self):
        from pbsjson.datasets import build_datasets
        build_datasets(Config())   # raises if names.json is missing a tuple


@unittest.skipUnless(os.path.isdir(ESSENTIALS_PBS), "Essentials PBS files not available")
class EssentialsRoundTripTest(unittest.TestCase):
    """Imports the Essentials PBS files and writes them back."""

    @classmethod
    def setUpClass(cls):
        cls.config = Config()
        cls.tmp = tempfile.mkdtemp(prefix="pbs_json_test_")
        cls.src = os.path.join(cls.tmp, "src")
        cls.out = os.path.join(cls.tmp, "out")
        cls.data = read_pbs_dir(cls.config, ESSENTIALS_PBS, quiet)
        write_json_tree(cls.src, cls.data, quiet)
        cls.loaded = load_json_tree(cls.config, cls.src)
        export_pbs(render_pbs(cls.loaded), cls.out, True, quiet)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def test_json_is_stable(self):
        """PBS -> JSON -> PBS -> JSON gives the same JSON."""
        src2 = os.path.join(self.tmp, "src2")
        write_json_tree(src2, read_pbs_dir(self.config, self.out, quiet), quiet)
        for dirpath, _, files in os.walk(self.src):
            for name in files:
                a = os.path.join(dirpath, name)
                b = os.path.join(src2, os.path.relpath(a, self.src))
                with open(a, "rb") as fa, open(b, "rb") as fb:
                    self.assertEqual(fa.read(), fb.read(), os.path.relpath(a, self.src))

    def test_pbs_text_matches(self):
        """Exported PBS files match the originals apart from comments.

        Two files differ only the way the engine's own writer would rewrite
        them: pokemon(_forms).txt use one "Evolution" line per evolution, and
        Battle Tower trainers are written in the writer's key order.
        """
        reordered = re.compile(r"(battle_tower|cup_.*)_trainers")
        for name in sorted(os.listdir(ESSENTIALS_PBS)):
            if not name.endswith(".txt"):
                continue
            original = normalized_lines(os.path.join(ESSENTIALS_PBS, name))
            exported = normalized_lines(os.path.join(self.out, name))
            if name in ("pokemon.txt", "pokemon_forms.txt"):
                original = [l for l in original if not l.startswith("Evolutions = ")]
                exported = [l for l in exported if not l.startswith("Evolution = ")]
            if reordered.match(name):
                original, exported = sorted(original), sorted(exported)
            self.assertEqual(original, exported, name)

    def test_evolutions_survive(self):
        species = {d.name: d for d in self.loaded}["pokemon"]
        eevee = next(e for e in species.entries() if e["id"] == "EEVEE")
        methods = [(e["species"], e["method"], e.get("parameter")) for e in eevee["evolutions"]]
        self.assertIn(("VAPOREON", "Item", "WATERSTONE"), methods)
        self.assertIn(("ESPEON", "HappinessDay", None), methods)
        bulbasaur = next(e for e in species.entries() if e["id"] == "BULBASAUR")
        self.assertEqual(bulbasaur["evolutions"][0]["parameter"], 16)

    def test_sprite_metrics_are_not_scaled(self):
        """Metrics are 1x game pixels already: copied as written."""
        metrics = {d.name: d for d in self.loaded}["pokemon_metrics"]
        bulbasaur = next(e for e in metrics.entries() if e.get("species") == "BULBASAUR")
        with open(os.path.join(ESSENTIALS_PBS, "pokemon_metrics.txt"), encoding="utf-8-sig") as f:
            text = f.read()
        section = text.split("[BULBASAUR]")[1].split("[")[0]
        back = re.search(r"BackSprite = (-?\d+),(-?\d+)", section)
        self.assertEqual(bulbasaur["back_sprite"], {"x": int(back.group(1)), "y": int(back.group(2))})

    def test_big_datasets_are_split(self):
        self.assertTrue(os.path.isfile(os.path.join(self.src, "pokemon", "bulbasaur.json")))
        self.assertTrue(os.path.isfile(os.path.join(self.src, "pokemon", "_index.json")))
        self.assertTrue(os.path.isfile(os.path.join(self.src, "types.json")))
        with open(os.path.join(self.src, "pokemon", "_index.json"), encoding="utf-8") as f:
            index = json.load(f)
        self.assertEqual(index["files"][0]["entries"][:3], ["bulbasaur", "ivysaur", "venusaur"])

    def test_snake_case_keys(self):
        with open(os.path.join(self.src, "trainer_types", "pokemontrainer_red.json"), encoding="utf-8") as f:
            entry = json.load(f)
        for key in entry:
            if key != "$schema":
                self.assertRegex(key, r"^[a-z0-9_]+$")

    def test_essentials_data_is_valid(self):
        problems = validate(self.config, self.loaded, self.src)
        errors = [str(p) for p in problems if not p.warning]
        self.assertEqual(errors, [])


class SmallTreeTest(unittest.TestCase):
    """Import/export behaviour on small PBS folders."""

    TYPES = ("[NORMAL]\nName = Normal\nIconPosition = 0\nWeaknesses = FIGHTING\n"
             "[FIGHTING]\nName = Fighting\nIconPosition = 1\n")
    MOVES = ("[TACKLE]\nName = Tackle\nType = NORMAL\nCategory = Physical\nPower = 40\n"
             "Accuracy = 100\nTotalPP = 35\nTarget = NearOther\nFunctionCode = None\n"
             "Description = A full-body charge attack.\n")

    def setUp(self):
        self.config = Config()
        self.tmp = tempfile.mkdtemp(prefix="pbs_json_small_")
        self.pbs = os.path.join(self.tmp, "pbs")
        self.src = os.path.join(self.tmp, "src")
        os.makedirs(self.pbs)
        self.write("types.txt", self.TYPES)
        self.write("moves.txt", self.MOVES)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def write(self, name, text, folder=None):
        path = os.path.join(folder or self.pbs, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        return path

    def import_tree(self, folder=None):
        write_json_tree(self.src, read_pbs_dir(self.config, folder or self.pbs, quiet), quiet)
        return load_json_tree(self.config, self.src)

    def test_backup_folders_are_ignored(self):
        self.write("pokemon.txt", "this is not valid PBS", os.path.join(self.pbs, "Gen 5 backup"))
        names = [d.name for d in self.import_tree()]
        self.assertEqual(sorted(names), ["moves", "types"])
        self.assertFalse(os.path.exists(os.path.join(self.src, "pokemon")))

    def test_old_key_names_are_read(self):
        self.write("moves.txt", self.MOVES.replace("Power = 40", "BaseDamage = 40"))
        moves = {d.name: d for d in self.import_tree()}["moves"]
        self.assertEqual(next(moves.entries())["power"], 40)

    def test_validation_finds_problems(self):
        self.import_tree()
        path = os.path.join(self.src, "moves", "tackle.json")
        with open(path, encoding="utf-8") as f:
            entry = json.load(f)
        entry["type"] = "FAIRY"
        entry["power"] = -5
        entry["colour"] = "red"
        with open(path, "w", encoding="utf-8") as f:
            json.dump(entry, f)
        self.write("stray.json", "{}", os.path.join(self.src, "moves"))
        problems = [str(p) for p in validate(self.config, load_json_tree(self.config, self.src), self.src)]
        text = "\n".join(problems)
        self.assertIn("undefined Type 'FAIRY'", text)
        self.assertIn("(power): must be 0 or greater", text)
        self.assertIn("unknown key 'colour'", text)
        self.assertIn("stray.json", text)

    def test_duplicates_are_found(self):
        self.write("types.txt", self.TYPES + "[NORMAL]\nName = Normal again\nIconPosition = 2\n")
        problems = [str(p) for p in validate(self.config, self.import_tree(), self.src)]
        self.assertTrue(any("defined twice" in p for p in problems), problems)

    def test_export_refuses_to_overwrite_editor_changes(self):
        out = os.path.join(self.tmp, "build_pbs")
        loaded = self.import_tree()
        written, conflicts = export_pbs(render_pbs(loaded), out, False, quiet)
        self.assertEqual(conflicts, [])
        self.assertTrue(os.path.isfile(os.path.join(out, STATE_FILE)))
        # The in-game editor rewrites moves.txt in build/PBS.
        moves = os.path.join(out, "moves.txt")
        with open(moves, encoding="utf-8-sig") as f:
            text = f.read()
        self.write("moves.txt", text.replace("Power = 40", "Power = 50"), out)
        _, conflicts = export_pbs(render_pbs(load_json_tree(self.config, self.src)), out, False, quiet)
        self.assertEqual(conflicts, ["moves.txt"])
        # make pull-pbs: import the editor's change, then exporting works.
        from pbsjson.store import accept_pbs_dir
        loaded = self.import_tree(out)
        accept_pbs_dir(out, ["moves.txt", "types.txt"])
        self.assertEqual(next({d.name: d for d in loaded}["moves"].entries())["power"], 50)
        _, conflicts = export_pbs(render_pbs(loaded), out, False, quiet)
        self.assertEqual(conflicts, [])

    def test_unknown_pbs_files_are_kept_as_text(self):
        self.write("my_plugin_data.txt", "[THING]\nValue = 1\n")
        out = os.path.join(self.tmp, "out")
        loaded = self.import_tree()
        self.assertTrue(os.path.isfile(os.path.join(self.src, "raw", "my_plugin_data.txt")))
        export_pbs(render_pbs(loaded), out, True, quiet)
        with open(os.path.join(out, "my_plugin_data.txt"), encoding="utf-8") as f:
            self.assertEqual(f.read(), "[THING]\nValue = 1\n")

    def test_suffix_files_keep_their_file(self):
        self.write("moves_extra.txt", self.MOVES.replace("TACKLE", "SLAM").replace("Tackle", "Slam"))
        out = os.path.join(self.tmp, "out")
        loaded = self.import_tree()
        with open(os.path.join(self.src, "moves", "_index.json"), encoding="utf-8") as f:
            index = json.load(f)
        self.assertEqual([(f["suffix"], f["entries"]) for f in index["files"]],
                         [("", ["tackle"]), ("extra", ["slam"])])
        export_pbs(render_pbs(loaded), out, True, quiet)
        self.assertTrue(os.path.isfile(os.path.join(out, "moves_extra.txt")))


if __name__ == "__main__":
    unittest.main()
