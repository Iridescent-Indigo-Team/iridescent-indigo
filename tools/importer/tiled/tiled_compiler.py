#!/usr/bin/env python3
"""Compiles the Tiled maps in src/tiled into the game's data, and imports
RPG Maker XP data into Tiled.

Usage: tiled_compiler.py [--src SRC] COMMAND ...
Run with --help for the commands. See docs/TILED.md.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from tiledc.cli import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main())
