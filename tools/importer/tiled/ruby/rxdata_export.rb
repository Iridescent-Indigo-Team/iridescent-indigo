#!/usr/bin/env ruby
#===============================================================================
# rxdata_export.rb DATA_DIR OUT_JSON [--only-tilesets]
#-------------------------------------------------------------------------------
# Reads RPG Maker XP data (MapInfos, Map###, Tilesets, CommonEvents, System
# .rxdata) and writes it as one JSON document for the Python importer
# (tiled_compiler.py import). Event commands are written as Ruby source (see
# tiled_rmxp.rb), so the importer can save them straight into .rb files.
#
# JSON layout:
#   { "mapinfos": {id: {name, parent_id, order, expanded, scroll_x, scroll_y}},
#     "tilesets": [ {id, name, tileset_name, autotile_names, panorama_*, fog_*,
#                    battleback_name, passages, priorities, terrain_tags} ],
#     "maps": {id: {width, height, tileset_id, autoplay_bgm, bgm, autoplay_bgs,
#                   bgs, encounter_list, encounter_step, data,
#                   events: [{id, name, x, y, pages: [settings], source}]}},
#     "common_events": [{id, name, source}],
#     "system": <System as JSON values> }
#===============================================================================
require_relative "tiled_rmxp"

module RxdataExport
  module_function

  # @param audio [RPG::AudioFile]
  # @return [Hash]
  def audio(audio)
    return { "name" => TiledRmxp.utf8(audio.name), "volume" => audio.volume, "pitch" => audio.pitch }
  end

  # Page settings (everything except commands and the move route).
  # @param page [RPG::Event::Page]
  # @return [Hash]
  def page_settings(page)
    c = page.condition
    g = page.graphic
    return {
      "switch1" => c.switch1_valid ? c.switch1_id : 0,
      "switch2" => c.switch2_valid ? c.switch2_id : 0,
      "variable" => c.variable_valid ? c.variable_id : 0,
      "variable_value" => c.variable_valid ? c.variable_value : 0,
      "self_switch" => c.self_switch_valid ? c.self_switch_ch : "",
      "tile_id" => g.tile_id,
      "character_name" => TiledRmxp.utf8(g.character_name),
      "character_hue" => g.character_hue,
      "direction" => g.direction,
      "pattern" => g.pattern,
      "opacity" => g.opacity,
      "blend_type" => g.blend_type,
      "move_type" => page.move_type,
      "move_speed" => page.move_speed,
      "move_frequency" => page.move_frequency,
      "walk_anime" => page.walk_anime,
      "step_anime" => page.step_anime,
      "direction_fix" => page.direction_fix,
      "through" => page.through,
      "always_on_top" => page.always_on_top,
      "trigger" => page.trigger
    }
  end

  # @param tileset [RPG::Tileset]
  # @return [Hash]
  def tileset(ts)
    return {
      "id" => ts.id, "name" => TiledRmxp.utf8(ts.name), "tileset_name" => TiledRmxp.utf8(ts.tileset_name),
      "autotile_names" => ts.autotile_names.map { |n| TiledRmxp.utf8(n) },
      "panorama_name" => TiledRmxp.utf8(ts.panorama_name), "panorama_hue" => ts.panorama_hue,
      "fog_name" => TiledRmxp.utf8(ts.fog_name), "fog_hue" => ts.fog_hue, "fog_opacity" => ts.fog_opacity,
      "fog_blend_type" => ts.fog_blend_type, "fog_zoom" => ts.fog_zoom, "fog_sx" => ts.fog_sx, "fog_sy" => ts.fog_sy,
      "battleback_name" => TiledRmxp.utf8(ts.battleback_name),
      "passages" => ts.passages.data, "priorities" => ts.priorities.data, "terrain_tags" => ts.terrain_tags.data
    }
  end

  def main(args)
    if args.length < 2
      warn("Usage: ruby #{File.basename(__FILE__)} DATA_DIR OUT_JSON [--only-tilesets]")
      return 2
    end
    dir, out = args
    only_tilesets = args.include?("--only-tilesets")
    result = { "mapinfos" => {}, "tilesets" => [], "maps" => {}, "common_events" => [], "system" => nil }
    tilesets_path = File.join(dir, "Tilesets.rxdata")
    if File.file?(tilesets_path)
      TiledRmxp.load(tilesets_path).each { |ts| result["tilesets"] << tileset(ts) if ts }
    end
    unless only_tilesets
      infos = TiledRmxp.load(File.join(dir, "MapInfos.rxdata"))
      infos.each do |id, info|
        result["mapinfos"][id.to_s] = {
          "name" => TiledRmxp.utf8(info.name), "parent_id" => info.parent_id, "order" => info.order,
          "expanded" => info.expanded, "scroll_x" => info.scroll_x, "scroll_y" => info.scroll_y
        }
      end
      dumper = TiledRmxp::Dumper.new
      infos.keys.sort.each do |id|
        path = File.join(dir, format("Map%03d.rxdata", id))
        next unless File.file?(path)
        map = TiledRmxp.load(path)
        name = TiledRmxp.utf8(infos[id].name)
        events = map.events.keys.sort.map do |eid|
          ev = map.events[eid]
          {
            "id" => ev.id, "name" => TiledRmxp.utf8(ev.name), "x" => ev.x, "y" => ev.y,
            "pages" => ev.pages.map { |pg| page_settings(pg) },
            "source" => dumper.event_file(ev, "Event #{ev.id} \"#{TiledRmxp.utf8(ev.name)}\" on #{name} (map #{id})")
          }
        end
        result["maps"][id.to_s] = {
          "width" => map.width, "height" => map.height, "tileset_id" => map.tileset_id,
          "autoplay_bgm" => map.autoplay_bgm, "bgm" => audio(map.bgm),
          "autoplay_bgs" => map.autoplay_bgs, "bgs" => audio(map.bgs),
          "encounter_list" => map.encounter_list, "encounter_step" => map.encounter_step,
          "data" => map.data.data, "events" => events
        }
      end
      ce_path = File.join(dir, "CommonEvents.rxdata")
      if File.file?(ce_path)
        TiledRmxp.load(ce_path).each do |ce|
          next unless ce
          result["common_events"] << { "id" => ce.id, "name" => TiledRmxp.utf8(ce.name),
                                       "source" => dumper.common_event_file(ce) }
        end
      end
      sys_path = File.join(dir, "System.rxdata")
      result["system"] = TiledRmxp.to_json_value(TiledRmxp.load(sys_path)) if File.file?(sys_path)
    end
    File.write(out, JSON.generate(result))
    return 0
  end
end

exit(RxdataExport.main(ARGV)) if $PROGRAM_NAME == __FILE__
