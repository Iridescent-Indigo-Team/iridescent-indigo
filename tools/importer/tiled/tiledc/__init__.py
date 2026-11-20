"""@package tiledc
Tiled integration for Pokessentials: compiles Tiled maps (.tmj), tilesets
(.tsj), event scripts (.rb) and atmospheres into the RPG Maker XP data and PBS
files the engine reads, and imports existing .rxdata into Tiled.

Plain Python 3 (stdlib only); Pillow is needed only for image work (autotile
conversion, combined tilesets, event previews). The .rxdata side is handled by
the Ruby helpers in tools/importer/tiled/ruby.
"""
