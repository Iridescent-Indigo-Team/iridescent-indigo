"""Tests of the Tiled tools (make test-tiled).

Most tests build a small Tiled project in a temporary folder. The round trip
test halves the Essentials sample data in lib/pokemon-essentials (when it's
there) to 1x like install_assets.sh does, imports it, compiles it back and
checks nothing the game uses changed.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

from tiledc import atmosphere, autotiles, config, connections, downscale, events, pbsmaps, stairs
from tiledc.compiler import Project, compile_map, compile_project
from tiledc.config import Paths
from tiledc.problems import Problems
from tiledc.registry import Registry
from tiledc.tiledio import load_json, make_prop, save_json, set_props, tile_layer
from tiledc.tiles import TerrainTags, from_tile_data, to_tile_data

HERE = os.path.dirname(os.path.abspath(__file__))
ESSENTIALS = os.path.join(config.ROOT, "lib", "pokemon-essentials")
HAVE_RUBY = shutil.which("ruby") is not None
try:
    import PIL  # noqa: F401
    HAVE_PIL = True
except ImportError:
    HAVE_PIL = False

FLIP_H = 0x80000000
## Tile size (16px).
T = config.TILE


class Sandbox:
    """A temporary Tiled project: two regular tilesets and one autotile."""

    def __init__(self):
        self.root = tempfile.mkdtemp(prefix="tiled_test_")
        self.paths = Paths(os.path.join(self.root, "tiled"))
        self.graphics = os.path.join(self.root, "graphics")
        self.old_graphics = config.GRAPHICS
        config.GRAPHICS = self.graphics
        for folder in (self.paths.maps, self.paths.autotiles, os.path.join(self.graphics, "Tilesets"),
                       os.path.join(self.graphics, "Autotiles")):
            os.makedirs(folder, exist_ok=True)
        self.tileset("a", 16, {3: {"block_down": True, "block_left": True, "block_right": True, "block_up": True},
                               5: {"terrain_tag": "Water"}})
        self.tileset("b", 8, {0: {"priority": 1}})
        sea = autotiles.tileset_json("Sea", os.path.join(self.paths.autotiles, "sea.png"),
                                     os.path.join(self.paths.autotiles, "sea.tsj"), 1, False, "Sea")
        set_props(sea, [make_prop("TileData", {"terrain_tag": "Water"}, "class", "TileData")])
        save_json(os.path.join(self.paths.autotiles, "sea.tsj"), sea)
        if HAVE_PIL:
            from PIL import Image
            Image.new("RGBA", (3 * T, 4 * T), (0, 0, 255, 255)).save(os.path.join(self.graphics, "Autotiles", "Sea.png"))
        self.registry = Registry(self.paths.registry, [])

    def cleanup(self):
        config.GRAPHICS = self.old_graphics
        shutil.rmtree(self.root, ignore_errors=True)

    def tileset(self, name, count, data, columns=8, tile=T):
        image = os.path.join(self.graphics, "Tilesets", name + ".png")
        rows = (count + columns - 1) // columns
        if HAVE_PIL:
            from PIL import Image
            Image.new("RGBA", (columns * tile, rows * tile), (255, 0, 0, 255)).save(image)
        tiles = [{"id": k, "properties": [make_prop("TileData", v, "class", "TileData")]} for k, v in data.items()]
        doc = {"columns": columns, "image": os.path.relpath(image, self.paths.tilesets), "imageheight": rows * tile,
               "imagewidth": columns * tile, "margin": 0, "name": name, "spacing": 0, "tilecount": count,
               "tileheight": tile, "tilewidth": tile, "type": "tileset", "tiles": tiles}
        save_json(os.path.join(self.paths.tilesets, name + ".tsj"), doc)

    def map(self, map_id, name, width=4, height=3, layers=None, tilesets=("a", "b", "sea"), objects=(),
            properties=(), **extra):
        """Writes a map. layers: list of flat gid lists."""
        entry = self.registry.by_id(map_id) or self.registry.add(name, map_id=map_id)
        path = self.registry.map_path(entry)
        refs, gid = [], 1
        counts = {"a": 16, "b": 8, "sea": 48}
        for t in tilesets:
            src = "../tilesets/autotiles/sea.tsj" if t == "sea" else "../tilesets/%s.tsj" % t
            refs.append({"firstgid": gid, "source": src})
            gid += counts[t]
        layers = layers if layers is not None else [[0] * (width * height)]
        doc = {"class": "Map", "height": height, "infinite": False, "orientation": "orthogonal",
               "tileheight": T, "tilewidth": T, "tilesets": refs, "type": "map", "width": width,
               "layers": [tile_layer("L%d" % i, width, height, data, i + 1) for i, data in enumerate(layers)]
               + [{"id": 99, "name": "Events", "type": "objectgroup", "objects": list(objects)}],
               "nextobjectid": 100}
        doc.update(extra)
        if properties:
            set_props(doc, list(properties))
        save_json(path, doc)
        self.registry.save()
        return path

    def compile(self, map_id):
        project = Project(self.paths)
        problems = Problems()
        result = compile_map(project, project.registry.by_id(map_id), problems)
        return result, problems, project

    def write_world(self, placed):
        connections.save_world(self.paths.world, Registry.load(self.paths.registry), placed)


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def messages(problems):
    return [str(p) for p in problems.items if not p.warning]


class TileNumberingTest(unittest.TestCase):
    def setUp(self):
        self.box = Sandbox()

    def tearDown(self):
        self.box.cleanup()

    def test_gids_across_tilesets(self):
        # a: gids 1-16, b: 17-24, sea: 25-72
        self.box.map(1, "Town", 3, 1, [[2, 18, 25 + 5]])
        result, problems, project = self.box.compile(1)
        self.assertEqual(messages(problems), [])
        data = result.ir["data"]
        self.assertEqual(data[0], 384 + 1)            # tile 1 of a
        self.assertEqual(data[1], 384 + 2 * 8 + 1)    # b starts after a's 2 rows
        self.assertEqual(data[2], 48 + 5)             # autotile slot 0
        combined = project.combined[result.ir["tileset_id"]]
        passages, priorities, tags = combined.tables(TerrainTags())
        self.assertEqual(passages[384 + 3], 0x0F)
        self.assertEqual(tags[384 + 5], TerrainTags().number("Water"))
        self.assertEqual(priorities[384 + 16], 1)
        self.assertEqual(tags[48 + 7], TerrainTags().number("Water"))   # autotile default data
        self.assertEqual(combined.graphic_name(), "Tiled/%d" % combined.id)

    def test_single_tileset_uses_its_own_image(self):
        self.box.map(1, "Town", 1, 1, [[1]], tilesets=("a",))
        result, problems, project = self.box.compile(1)
        self.assertEqual(project.combined[result.ir["tileset_id"]].graphic_name(), "a")

    def test_tileset_ids_are_stable(self):
        self.box.map(1, "Town", 1, 1, [[1]])
        self.box.map(2, "House", 1, 1, [[1]], tilesets=("a",))
        r1, _, p1 = self.box.compile(1)
        p1.tileset_registry.save()
        r2, _, p2 = self.box.compile(2)
        p2.tileset_registry.save()
        again, _, _ = self.box.compile(1)
        self.assertEqual(r1.ir["tileset_id"], again.ir["tileset_id"])
        self.assertNotEqual(r1.ir["tileset_id"], r2.ir["tileset_id"])

    @unittest.skipUnless(HAVE_PIL, "Pillow isn't installed")
    def test_combined_image(self):
        self.box.map(1, "Town", 1, 1, [[1]])
        result, _, project = self.box.compile(1)
        out = project.combined[result.ir["tileset_id"]].write_image(os.path.join(self.box.root, "out"))
        from PIL import Image
        with Image.open(out) as im:
            self.assertEqual(im.size, (8 * T, 3 * T))    # 8 columns x (2 + 1 rows)

    @unittest.skipUnless(HAVE_PIL, "Pillow isn't installed")
    def test_tilesets_of_any_width_are_reflowed(self):
        self.box.tileset("wide", 32, {}, columns=16)
        self.box.map(1, "Town", 2, 1, [[16 + 1, 2]], tilesets=("a",))
        doc = load_json(self.box.registry.map_path(self.box.registry.by_id(1)))
        doc["tilesets"] = [{"firstgid": 1, "source": "../tilesets/wide.tsj"}]
        save_json(self.box.registry.map_path(self.box.registry.by_id(1)), doc)
        result, problems, project = self.box.compile(1)
        self.assertEqual(messages(problems), [])
        self.assertEqual(result.ir["data"][0], 384 + 16)   # local id 16 is row 2 of 8 columns
        self.assertTrue(project.combined[result.ir["tileset_id"]].graphic_name().startswith("Tiled/"))


class LayerTest(unittest.TestCase):
    def setUp(self):
        self.box = Sandbox()

    def tearDown(self):
        self.box.cleanup()

    def test_three_layers_keep_their_index(self):
        self.box.map(1, "Town", 1, 1, [[0], [0], [2]])
        result, problems, _ = self.box.compile(1)
        self.assertEqual(result.ir["data"], [0, 0, 384 + 1])

    def test_more_layers_are_packed(self):
        self.box.map(1, "Town", 2, 1, [[1, 0], [0, 0], [2, 0], [0, 3], [0, 0]])
        result, problems, _ = self.box.compile(1)
        self.assertEqual(messages(problems), [])
        # tile 0: two tiles -> layers 0 and 1; tile 1: one tile -> layer 0
        self.assertEqual(result.ir["data"], [384, 386, 385, 0, 0, 0])

    def test_four_tiles_on_one_tile_is_an_error(self):
        self.box.map(1, "Town", 1, 1, [[1], [2], [3], [4]])
        _, problems, _ = self.box.compile(1)
        self.assertTrue(any("at most 3" in m for m in messages(problems)))


class RulesTest(unittest.TestCase):
    def setUp(self):
        self.box = Sandbox()

    def tearDown(self):
        self.box.cleanup()

    def assertRejected(self, text, **kwargs):
        self.box.map(1, "Town", **kwargs)
        _, problems, _ = self.box.compile(1)
        self.assertTrue(any(text in m for m in messages(problems)), messages(problems))

    def test_flipped_tiles(self):
        self.assertRejected("flipped or rotated", width=1, height=1, layers=[[FLIP_H | 1]])

    def test_infinite_maps(self):
        self.assertRejected("infinite", infinite=True)

    def test_isometric_and_hexagonal_maps(self):
        self.assertRejected("orthogonal", orientation="isometric")
        self.assertRejected("orthogonal", orientation="hexagonal")

    def test_tile_size(self):
        self.assertRejected("%dx%d" % (T, T), tilewidth=48, tileheight=48)
        self.assertRejected("make downscale-assets", tilewidth=32, tileheight=32)

    def test_tileset_tile_size(self):
        self.box.tileset("big", 4, {}, tile=48)
        self.box.map(1, "Town", 1, 1)
        doc = load_json(self.box.registry.map_path(self.box.registry.by_id(1)))
        doc["tilesets"] = [{"firstgid": 1, "source": "../tilesets/big.tsj"}]
        save_json(self.box.registry.map_path(self.box.registry.by_id(1)), doc)
        _, problems, _ = self.box.compile(1)
        self.assertTrue(any("%dx%d" % (T, T) in m for m in messages(problems)))

    def test_embedded_tilesets(self):
        self.box.map(1, "Town", 1, 1)
        path = self.box.registry.map_path(self.box.registry.by_id(1))
        doc = load_json(path)
        doc["tilesets"] = [{"firstgid": 1, "name": "x", "tilecount": 1, "tilewidth": T, "tileheight": T,
                            "image": "x.png", "columns": 1}]
        save_json(path, doc)
        _, problems, _ = self.box.compile(1)
        self.assertTrue(any("embedded" in m for m in messages(problems)))

    def test_too_many_autotiles(self):
        for i in range(8):
            shutil.copy(os.path.join(self.box.paths.autotiles, "sea.tsj"),
                        os.path.join(self.box.paths.autotiles, "sea%d.tsj" % i))
        self.box.map(1, "Town", 1, 1)
        path = self.box.registry.map_path(self.box.registry.by_id(1))
        doc = load_json(path)
        doc["tilesets"] = [{"firstgid": 1 + 48 * i, "source": "../tilesets/autotiles/sea%d.tsj" % i} for i in range(8)]
        save_json(path, doc)
        _, problems, _ = self.box.compile(1)
        self.assertTrue(any("at most 7 autotiles" in m for m in messages(problems)))

    def test_autotile_animation_frames_cant_be_painted(self):
        tsj = os.path.join(self.box.paths.autotiles, "sea.tsj")
        save_json(tsj, autotiles.tileset_json("Sea", os.path.join(self.box.paths.autotiles, "sea.png"), tsj, 2,
                                              False, "Sea"))
        self.assertRejected("animation frames", width=1, height=1, layers=[[25 + 50]])


class AutotileTest(unittest.TestCase):
    def test_wang_ids_match_the_engine(self):
        path = os.path.join(config.SCRIPTS, "006_Map renderer", "004_TileDrawingHelper.rb")
        text = read(path)
        table = [int(x) for x in re.search(r"NEIGHBORS_TO_AUTOTILE_INDEX = \[(.*?)\]", text, re.S)
                 .group(1).replace(",", " ").split()]
        for mask in range(256):
            n, ne, e, se, s, sw, w, nw = [(mask >> i) & 1 for i in range(8)]
            want = [n, ne & n & e, e, se & s & e, s, sw & s & w, w, nw & n & w]
            self.assertEqual(autotiles.wang_id(table[mask]), want, "neighbours %d" % mask)

    def test_patterns_match_the_engine(self):
        path = os.path.join(config.SCRIPTS, "006_Map renderer", "004_TileDrawingHelper.rb")
        text = read(path)
        block = re.search(r"AUTOTILE_PATTERNS = \[(.*?)\n  \]", text, re.S).group(1)
        numbers = [int(x) for x in re.findall(r"\d+", block)]
        self.assertEqual([q for p in autotiles.PATTERNS for q in p], numbers)

    @unittest.skipUnless(HAVE_PIL, "Pillow isn't installed")
    def test_expand(self):
        from PIL import Image
        img, frames = autotiles.expand(Image.new("RGBA", (3 * T * 3, 4 * T)))
        self.assertEqual((frames, img.size), (3, (8 * T, 6 * T * 3)))
        img, frames = autotiles.expand(Image.new("RGBA", (4 * T, T)))
        self.assertEqual((frames, img.size), (4, (8 * T, 6 * T * 4)))

    def test_frame_duration(self):
        self.assertEqual(autotiles.frame_duration("Sea"), config.AUTOTILE_FRAME_DURATION)
        self.assertEqual(autotiles.frame_duration("Flowers[8]"), 8)


class TileDataTest(unittest.TestCase):
    def test_round_trip(self):
        tags = TerrainTags()
        for passage in (0, 0x0F, 0x01, 0x46, 0x80, 0x10):
            for priority in (0, 3):
                for tag in (0, 7, 99):
                    data = to_tile_data(passage, priority, tag, tags)
                    self.assertEqual(from_tile_data(data, tags), (passage, priority, tag))

    def test_terrain_tags_from_the_engine(self):
        tags = TerrainTags()
        self.assertEqual(tags.number("Water"), 7)
        self.assertEqual(tags.name(7), "Water")
        self.assertIsNone(tags.number("NotATag"))


class ConnectionsTest(unittest.TestCase):
    def test_touching_maps_connect(self):
        a = connections.Placed(1, 0, 10, 20, 15)
        b = connections.Placed(2, 4, 0, 30, 10)     # north of a, starting 4 tiles right
        self.assertEqual(connections.connection(a, b), [1, "N", 4, 2, "S", 0])
        c = connections.Placed(3, 20, 12, 5, 5)     # east of a, 2 tiles down
        self.assertEqual(connections.connection(a, c), [1, "E", 2, 3, "W", 0])
        d = connections.Placed(4, 21, 0, 5, 5)      # not touching
        self.assertIsNone(connections.connection(a, d))
        corner = connections.Placed(5, 20, 0, 5, 10)  # only a corner touches
        self.assertIsNone(connections.connection(a, corner))

    def test_layout_round_trip_of_essentials_connections(self):
        path = os.path.join(config.PBS_SRC, "map_connections.json")
        if not os.path.isfile(path):
            self.skipTest("no src/pbs/map_connections.json")
        conns = [[c["map"], c["side"], c["offset"], c["other_map"], c["other_side"], c["other_offset"]]
                 for f in load_json(path)["files"] for c in f["entries"]]
        ids = {c[0] for c in conns} | {c[3] for c in conns}
        for sizes in ({i: (20 + i % 7, 15 + i % 5) for i in ids}, {i: (40, 40) for i in ids},
                      {i: (10 + i % 3, 60 - i % 11) for i in ids}):
            placed, leftover = connections.layout(sizes, conns)
            got = connections.merge(connections.world_connections(placed.values()), leftover)
            self.assertEqual({tuple(c) for c in got}, {tuple(connections.normalise(c)) for c in conns})

    def test_explicit_connections(self):
        conns, errors = connections.parse_explicit("N 0 Route 1 S 4; W 2 7 E 0", {"Route 1": 5})
        self.assertEqual(errors, [])
        self.assertEqual(conns, [["N", 0, 5, "S", 4], ["W", 2, 7, "E", 0]])
        _, errors = connections.parse_explicit("N 0 Route 1 E 4", {"Route 1": 5})
        self.assertEqual(len(errors), 1)


class MapDataTest(unittest.TestCase):
    def test_encounters_round_trip(self):
        entry = {"map": 5, "version": 1, "types": [
            {"type": "Land", "step_chance": 21, "slots": [
                {"chance": 40, "species": "PIDGEY", "min_level": 15, "max_level": 18},
                {"chance": 60, "species": "NIDORANfE", "min_level": 3}]}]}
        name, value = pbsmaps.encounters_to_props(entry)
        self.assertEqual(name, "encounters_v1")
        back = pbsmaps.props_to_encounters(5, name, value, config.encounter_types(), Problems(), "x")
        self.assertEqual(back, entry)

    def test_bad_slot(self):
        problems = Problems()
        pbsmaps.props_to_encounters(1, "encounters", {"Land": {"slots": "PIDGEY 5"}}, config.encounter_types(),
                                    problems, "x")
        self.assertTrue(problems.errors())

    def test_metadata_round_trip(self):
        fields = pbsmaps.metadata_fields()
        if not fields:
            self.skipTest("no PBS schema")
        entry = {"id": 2, "real_name": "Lappet Town", "outdoor_map": True,
                 "town_map_position": {"region": 0, "x": 13, "y": 12}, "flags": ["A", "B"],
                 "weather": {"weather": "Rain", "chance": 30}}
        value = pbsmaps.metadata_to_props(entry, fields)
        self.assertEqual(pbsmaps.props_to_metadata(2, value, fields, Problems(), "x"), entry)
        # Tiled doesn't store members left at their default
        del value["town_map_position"]["region"]
        problems = Problems()
        pbsmaps.props_to_metadata(2, value, fields, problems, "x")
        self.assertTrue(problems.errors())


class EventTest(unittest.TestCase):
    def test_page_settings_round_trip(self):
        settings = {"switch1": 22, "switch2": 0, "variable": 3, "variable_value": 5, "self_switch": "A",
                    "tile_id": 0, "character_name": "NPC 01", "character_hue": 0, "direction": 4, "pattern": 1,
                    "opacity": 200, "blend_type": 1, "move_type": 1, "move_speed": 4, "move_frequency": 3,
                    "walk_anime": True, "step_anime": False, "direction_fix": True, "through": False,
                    "always_on_top": False, "trigger": 3}
        page = events.settings_to_page(settings, lambda t: "")
        back = events.page_to_settings(page, lambda r: 0, Problems(), "x", "")
        self.assertEqual(back, settings)

    def test_object_tile(self):
        self.assertEqual(events.object_tile({"x": 2 * T, "y": 3 * T})[:2], (2, 3))
        # a 32x32 character standing on tile (3, 5)
        self.assertEqual(events.object_tile({"gid": 1, "x": 40, "y": 96, "width": 32, "height": 32}), (3, 5, True))

    def test_standalone_round_trip(self):
        obj = events.new_event_object(4, 7, "Sign", 3, 2, [{"trigger": "action"}], "../events/x.rb")
        set_props(obj, [make_prop("text", "Hi")])
        text = events.export_event(obj, "page 0, [\n  text(param(:text)),\n]\n")
        header, script = events.read_standalone(text)
        self.assertEqual((header["name"], header["x"], header["y"], header["params"]), ("Sign", 3, 2, {"text": "Hi"}))
        self.assertIn("param(:text)", script)


class AtmosphereTest(unittest.TestCase):
    def test_group_values_are_game_pixels(self):
        problems = Problems()
        layer = atmosphere.compile_layer({"name": "mist", "graphic": "Fogs/Mist", "scroll_x": 10, "offset_y": 4,
                                          "blend": "add"}, problems, "x", "", check_graphics=False)
        self.assertEqual((layer["scroll_x"], layer["offset_y"], layer["blend"]), (10.0, 4.0, 1))
        self.assertEqual(messages(problems), [])

    def test_bad_layer(self):
        problems = Problems()
        atmosphere.compile_layer({"name": "", "graphic": "", "z": "middle", "blend": "multiply"}, problems, "x", "",
                                 check_graphics=False)
        self.assertEqual(len(messages(problems)), 4)

    def test_legacy_group(self):
        group = atmosphere.legacy_group({"name": "Cave", "panorama_name": "Sky", "panorama_hue": 0,
                                         "fog_name": "Mist", "fog_hue": 0, "fog_opacity": 64,
                                         "fog_blend_type": 1, "fog_zoom": 200, "fog_sx": 2, "fog_sy": 0})
        self.assertEqual([l["name"] for l in group["layers"]], ["panorama", "fog"])
        self.assertEqual(group["layers"][1]["scroll_x"], 10)   # fog_sx * 5 pixels per second

    @unittest.skipUnless(HAVE_RUBY, "Ruby isn't installed")
    def test_runtime_manager(self):
        proc = subprocess.run(["ruby", os.path.join(HERE, "atmosphere_test.rb")], stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT)
        self.assertEqual(proc.returncode, 0, proc.stdout.decode("utf-8", "replace"))

    @unittest.skipUnless(HAVE_RUBY, "Ruby isn't installed")
    def test_runtime_renderer(self):
        proc = subprocess.run(["ruby", os.path.join(HERE, "renderer_test.rb")], stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT)
        self.assertEqual(proc.returncode, 0, proc.stdout.decode("utf-8", "replace"))


class StairsTest(unittest.TestCase):
    """Validator rules for sideways stairs (tiledc/stairs.py)."""

    ## gids in tileset "a" (local id + 1)
    WALL, LEFT, RIGHT, LEFT_BLOCKED = 4, 9, 10, 11

    def setUp(self):
        self.box = Sandbox()
        wall = {"block_down": True, "block_left": True, "block_right": True, "block_up": True}
        self.box.tileset("a", 16, {3: wall, 5: {"terrain_tag": "Water"},
                                   8: {"terrain_tag": "StairsLeft"}, 9: {"terrain_tag": "StairsRight"},
                                   10: {"terrain_tag": "StairsLeft", "block_left": True}})

    def tearDown(self):
        self.box.cleanup()

    def flight(self, cells, width=5, height=4, objects=()):
        """Compiles a map with the given {(x, y): gid} tiles. @return (result, problems)"""
        layer = [0] * (width * height)
        for (x, y), gid in cells.items():
            layer[x + y * width] = gid
        self.box.map(1, "Town", width, height, [layer], objects=objects)
        result, problems, _ = self.box.compile(1)
        return result, problems

    def stair_problems(self, problems, warnings):
        return [str(p) for p in problems.items if p.warning == warnings and
                re.search(r"stair|flight|landing|boulder", p.message)]

    def left_flight(self):
        return {(3, 3): self.LEFT, (2, 2): self.LEFT, (1, 1): self.LEFT}

    def test_valid_flights(self):
        cells = self.left_flight()
        result, problems = self.flight(cells)
        self.assertEqual(self.stair_problems(problems, False) + self.stair_problems(problems, True), [])
        self.assertEqual(result.stair_map.stairs, {(3, 3): "left", (2, 2): "left", (1, 1): "left"})
        cells = {(1, 3): self.RIGHT, (2, 2): self.RIGHT, (3, 1): self.RIGHT}
        _, problems = self.flight(cells)
        self.assertEqual(self.stair_problems(problems, False) + self.stair_problems(problems, True), [])

    def test_terrain_tags_from_the_engine(self):
        tags = TerrainTags()
        self.assertEqual(tags.number("StairsLeft"), 18)
        self.assertEqual(tags.number("StairsRight"), 19)

    def test_one_tile_flight(self):
        _, problems = self.flight({(2, 2): self.LEFT})
        self.assertTrue(any("walked like flat ground" in m for m in self.stair_problems(problems, True)))

    def test_blocked_stair(self):
        cells = self.left_flight()
        cells[(2, 2)] = self.LEFT_BLOCKED
        _, problems = self.flight(cells)
        self.assertTrue(any("blocks walking left or right" in m for m in self.stair_problems(problems, False)))

    def test_missing_landing(self):
        cells = self.left_flight()
        cells[(4, 3)] = self.WALL
        _, problems = self.flight(cells)
        warnings = self.stair_problems(problems, True)
        self.assertTrue(any("bottom end of this flight has no landing" in m for m in warnings), warnings)
        self.assertFalse(any("top end" in m for m in warnings), warnings)

    def test_flight_end_at_the_map_edge(self):
        _, problems = self.flight({(4, 3): self.LEFT, (3, 2): self.LEFT})
        self.assertEqual(self.stair_problems(problems, True), [])

    def test_spawn_on_stairs(self):
        spawn = {"class": "Spawn", "id": 1, "name": "door", "x": 2 * T, "y": 2 * T, "width": T, "height": T}
        _, problems = self.flight(self.left_flight(), objects=[spawn])
        self.assertTrue(any("spawn 'door'" in m for m in self.stair_problems(problems, False)))

    def test_boulder_on_stairs(self):
        shutil.copytree(os.path.join(config.ROOT, "src", "tiled", "templates"), self.box.paths.templates)
        on = {"id": 1, "template": "../templates/strength_boulder.tx", "x": 2 * T, "y": 2 * T}
        off = {"id": 2, "template": "../templates/strength_boulder.tx", "x": 0, "y": 3 * T}
        _, problems = self.flight(self.left_flight(), objects=[on, off])
        errors = [m for m in self.stair_problems(problems, False) if "boulder" in m]
        self.assertEqual(len(errors), 1, errors)

    def test_start_position_on_stairs(self):
        result, _ = self.flight(self.left_flight())
        problems = Problems()
        stairs.check_start({"start_map_id": 1, "start_x": 2, "start_y": 2}, [result], problems, "system.json")
        self.assertTrue(any("start position" in m for m in messages(problems)))
        problems = Problems()
        stairs.check_start({"start_map_id": 1, "start_x": 0, "start_y": 3}, [result], problems, "system.json")
        self.assertEqual(messages(problems), [])

    @unittest.skipUnless(HAVE_RUBY, "Ruby isn't installed")
    def test_route_commands_round_trip(self):
        script = ("require '%s'; require '%s'; f = TiledRmxp::Factory.new(lambda { |m, s| [1, 0, 0, 2] }); "
                  "r = f.route(f.stairs_off, f.move_left, f.stairs_on); "
                  "puts r.list[0..2].map { |c| [c.code, c.parameters[0]].inspect }; "
                  "d = RPGDumper.new(name: 'test', maps: {}); puts r.list[0..2].map { |c| d.move(c, 0) }.join(',')"
                  % (os.path.join(config.RUBY_DIR, "tiled_rmxp.rb"),
                     os.path.join(config.ROOT, "lib", "eevee", "rmxp", "rpg_dumper.rb")))
        proc = subprocess.run(["ruby", "-e", script], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        out = proc.stdout.decode("utf-8", "replace")
        self.assertEqual(proc.returncode, 0, out)
        self.assertIn('[45, "stairs_off"]', out)
        self.assertIn('[45, "stairs_on"]', out)
        self.assertIn("stairs_off,move_left,stairs_on", out)

    @unittest.skipUnless(HAVE_RUBY, "Ruby isn't installed")
    def test_runtime_resolver(self):
        proc = subprocess.run(["ruby", os.path.join(HERE, "stairs_test.rb")], stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT)
        self.assertEqual(proc.returncode, 0, proc.stdout.decode("utf-8", "replace"))

    @unittest.skipUnless(HAVE_RUBY, "Ruby isn't installed")
    def test_followers(self):
        """Followers walk the leader's step history; following Pokémon rules."""
        proc = subprocess.run(["ruby", os.path.join(HERE, "following_pokemon_test.rb")], stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT)
        self.assertEqual(proc.returncode, 0, proc.stdout.decode("utf-8", "replace"))


@unittest.skipUnless(HAVE_RUBY, "Ruby isn't installed")
class BuildTest(unittest.TestCase):
    """Compiles a small project with templates, spawns and named transfers."""

    def setUp(self):
        self.box = Sandbox()
        shutil.copytree(os.path.join(config.ROOT, "src", "tiled", "templates"), self.box.paths.templates)

    def tearDown(self):
        self.box.cleanup()

    def placed(self, template, object_id, x, y, params=()):
        obj = {"id": object_id, "template": "../templates/%s.tx" % template, "x": x * T, "y": y * T}
        if params:
            obj["properties"] = [make_prop(k, v) for k, v in params]
        return obj

    def test_build(self):
        spawn = {"class": "Spawn", "id": 1, "name": "door", "x": T, "y": 2 * T, "width": T, "height": T,
                 "properties": [make_prop("direction", "up", "string", "SpawnDirection")]}
        self.box.map(2, "House", 4, 4, objects=[spawn])
        objs = [self.placed("door", 1, 1, 1, [("to", "House"), ("spawn", "door")]),
                self.placed("item_ball", 2, 2, 1, [("item", "POTION")]),
                self.placed("trainer", 3, 3, 1),
                self.placed("sign", 4, 0, 0, [("text", "Pokédex")])]
        for i, name in enumerate(sorted(os.listdir(self.box.paths.templates))):
            if name.endswith(".tx") and name not in ("door.tx", "warp_tile.tx", "item_ball.tx", "trainer.tx",
                                                     "sign.tx"):
                objs.append(self.placed(name[:-3], 10 + i, i % 4, 2))
        self.box.map(1, "Town", 4, 3, objects=objs,
                     properties=[make_prop("encounters", {"Land": {"slots": "100 PIDGEY 2-3"}}, "class", "Encounters"),
                                 make_prop("atmosphere", "mist")])
        os.makedirs(self.box.paths.atmospheres)
        os.makedirs(os.path.join(self.box.graphics, "Fogs"))
        open(os.path.join(self.box.graphics, "Fogs", "Mist.png"), "wb").close()
        save_json(os.path.join(self.box.paths.atmospheres, "mist.json"),
                  {"layers": [{"name": "mist", "graphic": "Fogs/Mist", "scroll_x": 8}]})
        self.box.write_world([connections.Placed(1, 0, 0, 4, 3), connections.Placed(2, 0, 3, 4, 4)])
        build = os.path.join(self.box.root, "build")
        problems = compile_project(self.box.paths, os.path.join(build, "Data"), os.path.join(build, "Graphics"),
                                   os.path.join(build, ".tiled", "pbs"), log=lambda m: None)
        self.assertEqual(messages(problems), [])
        script = ("require '%s'; m = TiledRmxp.load(ARGV[0]); "
                  "puts JSON.generate(m.events.values.sort_by(&:id).map { |e| "
                  "[e.id, e.name, e.x, e.y, e.pages.length, e.pages[0].list.map { |c| [c.code, c.parameters] }] })"
                  % os.path.join(config.RUBY_DIR, "tiled_rmxp.rb"))
        out = subprocess.run(["ruby", "-e", script, os.path.join(build, "Data", "Map001.rxdata")],
                             stdout=subprocess.PIPE, check=True).stdout.decode("utf-8")
        evs = {e[0]: e for e in json.loads(out)}
        transfer = [c for c in evs[1][5] if c[0] == 201][0]
        self.assertEqual(transfer[1], [0, 2, 1, 2, 8, 1])      # map 2, spawn at 1,2 facing up, no fade
        self.assertIn([111, [12, "pbItemBall(:POTION, 1)"]], evs[2][5])
        self.assertEqual(evs[2][4], 2)
        self.assertIn([108, ["Type: YOUNGSTER"]], evs[3][5])
        self.assertIn([101, ["Pokédex"]], evs[4][5])
        self.assertEqual((evs[2][2], evs[2][3]), (2, 1))
        # PBS overlay and atmosphere data
        enc = load_json(os.path.join(build, ".tiled", "pbs", "encounters", "map_001.json"))
        self.assertEqual(enc["types"][0]["slots"][0]["species"], "PIDGEY")
        conns = load_json(os.path.join(build, ".tiled", "pbs", "map_connections.json"))
        self.assertEqual(conns["files"][0]["entries"][0]["side"], "S")
        self.assertTrue(os.path.isfile(os.path.join(build, "Data", "atmospheres.dat")))
        self.assertTrue(os.path.isfile(os.path.join(build, "Data", "tiled_build.dat")))

    def test_script_errors_are_reported(self):
        os.makedirs(self.box.paths.events, exist_ok=True)
        bad = os.path.join(self.box.paths.events, "bad.rb")
        with open(bad, "w") as f:
            f.write("page 0, [\n  text(\"unclosed\",\n]\n")
        obj = events.new_event_object(1, 1, "Bad", 0, 0, [{}], "../events/bad.rb")
        missing = self.placed("door", 2, 1, 0, [("to", "Nowhere"), ("spawn", "x")])
        self.box.map(1, "Town", objects=[obj, missing])
        problems = compile_project(self.box.paths, check_only=True, log=lambda m: None)
        text = "\n".join(messages(problems))
        self.assertIn("bad.rb", text)
        self.assertIn("Nowhere", text)
        # A build with errors writes nothing
        data = os.path.join(self.box.root, "build", "Data")
        problems = compile_project(self.box.paths, data, None, os.path.join(self.box.root, "build", ".tiled", "pbs"),
                                   log=lambda m: None)
        self.assertTrue(problems.errors())
        self.assertFalse(os.path.exists(os.path.join(data, "Map001.rxdata")))


class DownscaleTest(unittest.TestCase):
    """One-time conversion of a 32px src/tiled (2x graphics) to 16px."""

    def setUp(self):
        self.box = Sandbox()

    def tearDown(self):
        self.box.cleanup()

    def test_picture_commands(self):
        text = ("page 0, [\n  show_picture(\n    number: 1,\n    graphic: \"a (x: 3)\",\n    origin: :center,\n"
                "    x: 256,\n    y: -171,\n    zoom_x: 200,\n    opacity: 0,\n  ),\n"
                "  move_picture(number: 1, frames: 5, origin: :center, x: 10, y: 4, blending: :normal),\n"
                "  show_picture_variables(number: 2, graphic: \"b\", origin: :center, x: 7, y: 8),\n"
                "  script(\"x: 40\"),\n]\n")
        odd = []
        out = downscale.halve_picture_commands(text, odd, "e.rb")
        self.assertIn("x: 128,\n    y: -86,\n    zoom_x: 200,", out)    # halves rounded away from zero
        self.assertIn('graphic: "a (x: 3)"', out)                       # strings are left alone
        self.assertIn("x: 5, y: 2, blending", out)
        self.assertIn("show_picture_variables(number: 2, graphic: \"b\", origin: :center, x: 7, y: 8)", out)
        self.assertIn('script("x: 40")', out)
        self.assertEqual(odd, ["e.rb:2: y = -171"])

    def test_project(self):
        self.box.tileset("a", 16, {}, tile=32)
        self.box.tileset("b", 8, {}, tile=32)
        sea = os.path.join(self.box.paths.autotiles, "sea.tsj")
        doc = load_json(sea)
        doc.update(tilewidth=32, tileheight=32, imagewidth=256, imageheight=192)
        save_json(sea, doc)
        door = {"class": "Event", "id": 1, "name": "door", "x": 64, "y": 64, "width": 32, "height": 32}
        path = self.box.map(1, "Town", 4, 3, objects=[door], tilewidth=32, tileheight=32)
        self.box.write_world([connections.Placed(1, 2, 1, 4, 3)])
        world = load_json(self.box.paths.world)
        world["maps"][0].update(x=64, y=32, width=128, height=96)
        save_json(self.box.paths.world, world)
        os.makedirs(self.box.paths.atmospheres)
        save_json(os.path.join(self.box.paths.atmospheres, "mist.json"),
                  {"layers": [{"name": "mist", "graphic": "Fogs/Mist", "scroll_x": 20, "offset_y": -8}]})

        self.assertTrue(downscale.downscale(self.box.paths, log=lambda m: None))
        m = load_json(path)
        self.assertEqual((m["tilewidth"], m["tileheight"]), (T, T))
        obj = m["layers"][-1]["objects"][0]
        self.assertEqual((obj["x"], obj["y"], obj["width"], obj["height"]), (32, 32, 16, 16))
        a = load_json(os.path.join(self.box.paths.tilesets, "a.tsj"))
        self.assertEqual((a["tilewidth"], a["imagewidth"], a["imageheight"]), (T, 8 * T, 2 * T))
        self.assertEqual(load_json(sea)["imageheight"], 96)
        self.assertEqual({k: load_json(self.box.paths.world)["maps"][0][k] for k in ("x", "y", "width", "height")},
                         {"x": 32, "y": 16, "width": 64, "height": 48})
        mist = load_json(os.path.join(self.box.paths.atmospheres, "mist.json"))["layers"][0]
        self.assertEqual((mist["scroll_x"], mist["offset_y"]), (10, -4))
        # It compiles, and running the conversion again changes nothing.
        self.assertEqual(messages(self.box.compile(1)[1]), [])
        self.assertFalse(downscale.downscale(self.box.paths, log=lambda m: None))

    def test_mixed_sizes_are_refused(self):
        self.box.map(1, "Town", tilewidth=32, tileheight=32)
        from tiledc.problems import TiledError
        with self.assertRaises(TiledError):
            downscale.downscale(self.box.paths, log=lambda m: None)


@unittest.skipUnless(HAVE_RUBY, "Ruby isn't installed")
class CommandPaletteTest(unittest.TestCase):
    """Every snippet of the Insert Event Command action is valid event code."""

    def test_snippets(self):
        js = read(os.path.join(config.ROOT, "src", "tiled", "extensions", "CreateRPGEvent.js"))
        block = re.search(r"var COMMANDS = \[(.*?)\n    \];", js, re.S).group(1)
        snippets = [json.loads(m) if m.startswith('"') else m[1:-1]
                    for m in re.findall(r"\[\"[^\"]+\", ('(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\")\]", block)]
        self.assertGreater(len(snippets), 15)
        body = ",\n".join(s.encode().decode("unicode_escape") for s in snippets)
        script = ("require '%s'; f = TiledRmxp::Factory.new(lambda { |m, s| [1, 0, 0, 2] }); "
                  "f.instance_eval(STDIN.read); puts f.pages[0].length" % os.path.join(config.RUBY_DIR, "tiled_rmxp.rb"))
        proc = subprocess.run(["ruby", "-e", script], input=("page 0, [\n%s\n]\n" % body).encode(),
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(proc.returncode, 0, proc.stderr.decode())


@unittest.skipUnless(HAVE_RUBY and os.path.isdir(os.path.join(ESSENTIALS, "Data")),
                     "needs Ruby and lib/pokemon-essentials")
class EssentialsRoundTripTest(unittest.TestCase):
    """Imports the Essentials sample game into Tiled and compiles it back."""

    @unittest.skipUnless(HAVE_PIL, "Pillow isn't installed")
    def test_round_trip(self):
        from tiledc.importer import import_rxdata
        root = tempfile.mkdtemp(prefix="tiled_rt_")
        old = config.GRAPHICS
        scripts = os.path.join(config.ROOT, "tools", "scripts")
        try:
            # Halve the 2x sample data and the graphics the maps use, like
            # install_assets.sh does.
            data = os.path.join(root, "Data")
            subprocess.run(["ruby", os.path.join(scripts, "halve_data.rb"), os.path.join(ESSENTIALS, "Data"), data],
                           check=True, stdout=subprocess.DEVNULL)
            config.GRAPHICS = os.path.join(root, "Graphics")
            for folder in ("Tilesets", "Autotiles", "Fogs", "Panoramas"):
                if not os.path.isdir(os.path.join(ESSENTIALS, "Graphics", folder)):
                    continue
                subprocess.run([sys.executable, "-I", os.path.join(scripts, "resize_graphics.py"),
                                os.path.join(ESSENTIALS, "Graphics", folder), os.path.join(config.GRAPHICS, folder),
                                "--report", os.path.join(root, "resize_report.txt")],
                               check=True, stdout=subprocess.DEVNULL)
            paths = Paths(os.path.join(root, "tiled"))
            import_rxdata(paths, data, keep_pbs=True, log=lambda m: None, warn=lambda m: None)
            build = os.path.join(root, "build")
            problems = compile_project(paths, os.path.join(build, "Data"), os.path.join(build, "Graphics"),
                                       os.path.join(build, ".tiled", "pbs"), log=lambda m: None)
            self.assertEqual(messages(problems), [])
            proc = subprocess.run(["ruby", os.path.join(config.RUBY_DIR, "roundtrip_check.rb"),
                                   data, os.path.join(build, "Data")],
                                  stdout=subprocess.PIPE)
            out = proc.stdout.decode("utf-8", "replace")
            summary = json.loads(out.strip().splitlines()[-1])
            self.assertEqual(summary["differences"], 0, out)
            self.assertGreater(summary["events"], 400)
            # Map metadata comes back exactly as src/pbs has it
            if os.path.isdir(os.path.join(config.PBS_SRC, "map_metadata")):
                for name in os.listdir(os.path.join(config.PBS_SRC, "map_metadata")):
                    a = read(os.path.join(config.PBS_SRC, "map_metadata", name))
                    b = read(os.path.join(build, ".tiled", "pbs", "map_metadata", name))
                    self.assertEqual(a, b, name)
        finally:
            config.GRAPHICS = old
            shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
