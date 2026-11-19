#!/usr/bin/env ruby
#===============================================================================
# write_messages.rb JSON CORE_DAT GAME_DAT
#-------------------------------------------------------------------------------
# Writes the Marshal'd message files of one language from the JSON made by
# locjson/compile.py:
#   {"core": {"<type>": {key: text}}, "game": {...}, "events": {"<map>": {...}},
#    "locale": {...}, "locale_index": 99, "event_index": 0}
# CORE_DAT and GAME_DAT get the Array layout Translation#load_message_files
# reads. A file is only rewritten when its contents change. Prints the paths
# written.
#===============================================================================
require "json"

# @param tables [Hash{String=>Hash}] message type -> {key => text}
# @return [Array]
def build_array(tables)
  ret = []
  tables.each { |type, hash| ret[type.to_i] = hash }
  ret
end

# @param path [String]
# @param data [Object]
# @return [Boolean] true if the file was written
def write_if_changed(path, data)
  bytes = Marshal.dump(data)
  return false if File.file?(path) && File.binread(path) == bytes
  File.binwrite(path, bytes)
  true
end

if ARGV.length != 3
  warn "usage: write_messages.rb JSON CORE_DAT GAME_DAT"
  exit 2
end
doc = JSON.parse(File.read(ARGV[0], encoding: "UTF-8"))
core = build_array(doc["core"])
game = build_array(doc["game"])
events = []
doc["events"].each { |map_id, hash| events[map_id.to_i] = hash }
game[doc["event_index"]] = events if !events.empty?
game[doc["locale_index"]] = doc["locale"]
puts ARGV[1] if write_if_changed(ARGV[1], core)
puts ARGV[2] if write_if_changed(ARGV[2], game)
