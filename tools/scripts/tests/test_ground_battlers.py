"""@package test_ground_battlers
Tests for tools/scripts/ground_battlers.py.

Run with `make test-ground-battlers`. The tests build small fake sprites and
metrics in a temporary folder, so they don't need installed art.
"""

import contextlib
import importlib.util
import io
import json
import os
import re
import shutil
import tempfile
import unittest

from PIL import Image

## Folder of the scripts being tested.
SCRIPTS = os.path.abspath(os.path.join(os.path.dirname(__file__), os.pardir))
## Root of the repository.
ROOT = os.path.abspath(os.path.join(SCRIPTS, os.pardir, os.pardir))


def _load_tool():
    spec = importlib.util.spec_from_file_location(
        "ground_battlers", os.path.join(SCRIPTS, "ground_battlers.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


## The tool under test.
gb = _load_tool()


def make_sprite(path, size, body):
    """Writes a transparent PNG with an opaque box.

    @param path where to write it
    @param size side of the square image (192 for 2x art, 288 for 3x art)
    @param body (left, top, right, bottom) of the opaque box, in image pixels
    """
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    img.paste((255, 0, 0, 255), body)
    img.save(path)


def write_entry(folder, stem, entry):
    entry = dict({"$schema": gb.METRICS_SCHEMA}, **entry)
    with open(os.path.join(folder, stem + ".json"), "w", encoding="utf-8") as f:
        f.write(gb.dumps(entry) + "\n")


def ruby_constant(rel, name):
    """Reads an integer constant from a game script."""
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        match = re.search(r"^\s*%s\s*=\s*(-?\d+)\s*$" % name, f.read(), re.M)
    return int(match.group(1))


class ConstantsTest(unittest.TestCase):
    def test_copies_match_the_game(self):
        scene = "src/data/011_Battle/004_Scene/001_Battle_Scene.rb"
        editor = "src/data/020_Debug/001_Editor screens/004_EditorScreens_SpritePositioning.rb"
        self.assertEqual(gb.PLAYER_FEET_OFFSET, ruby_constant(scene, "PLAYER_FEET_OFFSET"))
        self.assertEqual(gb.FOE_FEET_OFFSET, ruby_constant(scene, "FOE_FEET_OFFSET"))
        self.assertEqual(gb.CUT_OFF_RUN, ruby_constant(editor, "CUT_OFF_SPRITE_RUN"))


class GroundBattlersTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.graphics = os.path.join(self.tmp, "Graphics")
        self.src = os.path.join(self.tmp, "pbs")
        self.metrics = os.path.join(self.src, gb.METRICS_DIR)
        os.makedirs(self.metrics)

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def sprite(self, folder, name, size, body):
        make_sprite(os.path.join(self.graphics, "Pokemon", folder, name + ".png"), size, body)

    def index(self, stems):
        with open(os.path.join(self.metrics, gb.INDEX_FILE), "w", encoding="utf-8") as f:
            json.dump({"files": [{"suffix": "", "bom": False, "entries": stems}]}, f)

    def run_tool(self, *args):
        with contextlib.redirect_stdout(io.StringIO()):
            return gb.main(["--graphics", self.graphics, "--src", self.src] + list(args))

    def read(self, stem):
        with open(os.path.join(self.metrics, stem + ".json"), encoding="utf-8") as f:
            return json.load(f)

    def test_full_body_sprites_stand_on_the_ground_lines(self):
        # 3x back art: body ends at row 240 of 288 -> row 80 of 96 (gap 16).
        self.sprite("Back", "TESTMON", 288, (90, 60, 200, 240))
        # 2x front art: body ends at row 170 of 192 -> row 85 of 96 (gap 11).
        self.sprite("Front", "TESTMON", 192, (60, 80, 130, 170))
        write_entry(self.metrics, "testmon", {
            "species": "TESTMON", "back_sprite": {"x": 3, "y": 36},
            "front_sprite": {"x": -2, "y": 13}, "shadow_x": 0, "shadow_size": 2})
        self.index(["testmon"])
        self.assertEqual(self.run_tool(), 0)
        entry = self.read("testmon")
        self.assertEqual(entry["back_sprite"], {"x": 3, "y": 16 + gb.PLAYER_FEET_OFFSET})
        self.assertEqual(entry["front_sprite"], {"x": -2, "y": 11 + gb.FOE_FEET_OFFSET})
        self.assertNotIn("front_sprite_altitude", entry)
        # Running again changes nothing.
        self.assertEqual(self.run_tool("--check"), 0)

    def test_old_lift_becomes_altitude(self):
        self.sprite("Back", "FLOATY", 288, (90, 60, 200, 240))
        self.sprite("Front", "FLOATY", 192, (60, 80, 130, 170))
        # The old front y lifts the feet 20px above the ground line.
        write_entry(self.metrics, "floaty", {
            "species": "FLOATY", "back_sprite": {"x": 0, "y": 0},
            "front_sprite": {"x": 0, "y": 11 + gb.FOE_FEET_OFFSET - 20}})
        self.index(["floaty"])
        self.assertEqual(self.run_tool("--keep-hover"), 0)
        entry = self.read("floaty")
        self.assertEqual(entry["front_sprite_altitude"], 20)
        self.assertEqual(entry["front_sprite"]["y"], 11 + gb.FOE_FEET_OFFSET)
        # The back sprite floats by the same amount.
        self.assertEqual(entry["back_sprite"]["y"], 16 + gb.PLAYER_FEET_OFFSET - 20)
        self.assertEqual(self.run_tool("--check"), 0)

    def test_without_keep_hover_everything_is_grounded(self):
        self.sprite("Front", "FLOATY", 192, (60, 80, 130, 170))
        write_entry(self.metrics, "floaty", {
            "species": "FLOATY", "front_sprite": {"x": 0, "y": -10}})
        self.index(["floaty"])
        self.assertEqual(self.run_tool(), 0)
        entry = self.read("floaty")
        self.assertNotIn("front_sprite_altitude", entry)
        self.assertEqual(entry["front_sprite"]["y"], 11 + gb.FOE_FEET_OFFSET)

    def test_cut_off_back_sprite_stays_behind_message_box(self):
        # Old-style back sprite: 160x160 art cut off along its bottom edge.
        self.sprite("Back", "OLDMON", 160, (40, 30, 120, 160))
        write_entry(self.metrics, "oldmon", {
            "species": "OLDMON", "back_sprite": {"x": 0, "y": 5}})
        self.index(["oldmon"])
        self.assertEqual(self.run_tool(), 0)
        self.assertEqual(self.read("oldmon")["back_sprite"]["y"], 0)

    def test_feet_touching_bottom_are_not_cut_off(self):
        # A big full-body sprite whose two thin feet reach the bottom row.
        path = os.path.join(self.graphics, "Pokemon", "Back", "BIGMON.png")
        os.makedirs(os.path.dirname(path))
        img = Image.new("RGBA", (288, 288), (0, 0, 0, 0))
        img.paste((255, 0, 0, 255), (60, 30, 230, 250))
        img.paste((255, 0, 0, 255), (90, 250, 105, 288))   # 5px wide at 1x
        img.paste((255, 0, 0, 255), (180, 250, 195, 288))
        img.save(path)
        feet = gb.measure(path, "BIGMON.png")
        self.assertFalse(feet.cropped)
        self.assertEqual(gb.back_y(feet), gb.PLAYER_FEET_OFFSET)

    def test_new_form_entry_added_next_to_species(self):
        self.sprite("Front", "SHAPER", 192, (60, 80, 130, 170))
        self.sprite("Front", "SHAPER_1", 192, (60, 80, 130, 150))   # gap 21
        self.sprite("Front", "OTHER", 192, (60, 80, 130, 170))
        write_entry(self.metrics, "shaper", {"species": "SHAPER", "front_sprite": {"x": 1, "y": 0}})
        write_entry(self.metrics, "other", {"species": "OTHER", "front_sprite": {"x": 0, "y": 0}})
        self.index(["shaper", "other"])
        forms = os.path.join(self.src, gb.FORMS_DIR)
        os.makedirs(forms)
        with open(os.path.join(forms, "shaper_1.json"), "w", encoding="utf-8") as f:
            json.dump({"species": "SHAPER", "form": 1}, f)
        with open(os.path.join(forms, gb.INDEX_FILE), "w", encoding="utf-8") as f:
            json.dump({"files": [{"suffix": "", "bom": False, "entries": ["shaper_1"]}]}, f)
        self.assertEqual(self.run_tool("--new-forms"), 0)
        entry = self.read("shaper_1")
        self.assertEqual((entry["species"], entry["form"]), ("SHAPER", 1))
        self.assertEqual(entry["front_sprite"], {"x": 1, "y": 21 + gb.FOE_FEET_OFFSET})
        with open(os.path.join(self.metrics, gb.INDEX_FILE), encoding="utf-8") as f:
            self.assertEqual(json.load(f)["files"][0]["entries"], ["shaper", "shaper_1", "other"])

    def test_check_reports_changes_without_writing(self):
        self.sprite("Front", "TESTMON", 192, (60, 80, 130, 170))
        write_entry(self.metrics, "testmon", {"species": "TESTMON", "front_sprite": {"x": 0, "y": 0}})
        self.index(["testmon"])
        self.assertEqual(self.run_tool("--check"), 1)
        self.assertEqual(self.read("testmon")["front_sprite"]["y"], 0)


if __name__ == "__main__":
    unittest.main()
