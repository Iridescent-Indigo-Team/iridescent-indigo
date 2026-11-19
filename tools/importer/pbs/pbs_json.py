#!/usr/bin/env python3
"""Converts Pokémon Essentials PBS files to JSON and back.

Usage: python3 -I tools/importer/pbs/pbs_json.py [--src DIR] COMMAND ...

  import PBS_DIR   read PBS_DIR/*.txt into src/pbs (subfolders are ignored)
  export PBS_DIR   validate src/pbs and write PBS_DIR/*.txt
                   [--force] overwrite files changed since the last export
  validate         check src/pbs
  schema           regenerate the JSON Schemas in src/pbs/_schema
  roundtrip DIR    check that DIR -> JSON -> PBS -> JSON loses nothing

The PBS formats come from engine_schema.json, which the engine writes from
GameData::*::SCHEMA (`make pbs-schema`). See docs/PBS_JSON.md.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from pbsjson.cli import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main())
