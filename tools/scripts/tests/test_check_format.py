"""@package test_check_format
Tests for tools/scripts/check_format.py.

Run with `make test-ground-battlers` (it runs every test in tools/scripts/tests)
or `python3 -I -m unittest discover -s tools/scripts/tests -t tools/scripts`.
These tests don't need RuboCop.
"""

import importlib.util
import json
import os
import unittest

## Folder of the scripts being tested.
SCRIPTS = os.path.abspath(os.path.join(os.path.dirname(__file__), os.pardir))


def _load_tool():
    spec = importlib.util.spec_from_file_location(
        "check_format", os.path.join(SCRIPTS, "check_format.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


## The module being tested.
cf = _load_tool()


class ParseDiffTest(unittest.TestCase):
    def test_added_and_changed_lines(self):
        diff = "\n".join([
            "diff --git a/src/data/a.rb b/src/data/a.rb",
            "--- a/src/data/a.rb",
            "+++ b/src/data/a.rb",
            "@@ -3 +3 @@ def foo",
            "@@ -10,0 +11,2 @@",
            "@@ -20,3 +22,0 @@",
            "diff --git a/new.json b/new.json",
            "--- /dev/null",
            "+++ b/new.json",
            "@@ -0,0 +1,4 @@",
        ])
        self.assertEqual(cf.parse_diff(diff), {"src/data/a.rb": {3, 11, 12}, "new.json": {1, 2, 3, 4}})

    def test_deleted_file_is_ignored(self):
        diff = "--- a/gone.rb\n+++ /dev/null\n@@ -1,2 +0,0 @@\n"
        self.assertEqual(cf.parse_diff(diff), {})


class WantedTest(unittest.TestCase):
    def test_paths(self):
        self.assertTrue(cf.wanted("src/data/001_Technical/foo.rb"))
        self.assertTrue(cf.wanted("tools/scripts/halve_data.rb"))
        self.assertTrue(cf.wanted("src/pbs/items/potion.json"))
        self.assertTrue(cf.wanted("src/tiled/maps/map001.tmj"))
        self.assertFalse(cf.wanted("src/tiled/common_events/001_event.rb"))
        self.assertFalse(cf.wanted("lib/mkxp-z/mkxp.json"))
        self.assertFalse(cf.wanted("README.md"))


class JsonTest(unittest.TestCase):
    def test_comments_are_stripped_outside_strings(self):
        text = '{\n  // a comment\n  "url": "http://x", /* block\n */ "n": 1\n}'
        stripped = cf.strip_json_comments(text)
        self.assertEqual(json.loads(stripped), {"url": "http://x", "n": 1})
        self.assertEqual(stripped.count("\n"), text.count("\n"))

    def test_invalid_json(self):
        message, fixed = cf.check_json("tools/x.json", '{"a": 1,}')
        self.assertIn("tools/x.json:1:", message)
        self.assertIsNone(fixed)

    def test_mkxp_json_may_have_comments(self):
        self.assertEqual(cf.check_json("src/mkxp.json", '{\n  // c\n  "a": 1\n}\n'), (None, None))

    def test_pbs_layout(self):
        value = {"id": "POTION", "flags": ["Fling_30"], "price": 200}
        good = cf.pbs_store.dumps(value) + "\n"
        self.assertEqual(cf.check_json("src/pbs/items/potion.json", good), (None, None))
        message, fixed = cf.check_json("src/pbs/items/potion.json", json.dumps(value))
        self.assertIn("not in the layout", message)
        self.assertEqual(fixed, good)

    def test_tiled_layout(self):
        value = {"maps": [{"id": 1, "file": "map001.tmj"}]}
        good = cf.tiledio.dumps(value)
        self.assertEqual(cf.check_json("src/tiled/maps/registry.json", good), (None, None))
        _, fixed = cf.check_json("src/tiled/maps/registry.json", json.dumps(value, indent=4))
        self.assertEqual(fixed, good)

    def test_other_json_only_needs_to_be_valid(self):
        self.assertEqual(cf.check_json("tools/importer/x.json", '{"a":1}'), (None, None))


class RubyTest(unittest.TestCase):
    def _offense(self, line, last=None, cop="Layout/ExtraSpacing"):
        return {"cop_name": cop, "message": "m",
                "location": {"start_line": line, "last_line": last or line, "start_column": 1}}

    def test_only_offenses_on_changed_lines_count(self):
        self.assertTrue(cf.relevant(self._offense(5), {5}))
        self.assertFalse(cf.relevant(self._offense(4), {5}))
        self.assertTrue(cf.relevant(self._offense(3, 6), {5}))
        self.assertTrue(cf.relevant(self._offense(4), cf.ALL_LINES))
        self.assertTrue(cf.relevant(self._offense(1, cop="Lint/Syntax"), {5}))

    def test_merge_fixes_keeps_unchanged_lines(self):
        original = "a  = 1\nb  = 2\nc  = 3\n"
        corrected = "a = 1\nb = 2\nc = 3\n"
        self.assertEqual(cf.merge_fixes(original, corrected, {2}), "a  = 1\nb = 2\nc  = 3\n")
        self.assertEqual(cf.merge_fixes(original, corrected, cf.ALL_LINES), corrected)


if __name__ == "__main__":
    unittest.main()
