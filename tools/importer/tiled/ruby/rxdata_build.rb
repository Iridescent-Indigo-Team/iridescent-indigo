#!/usr/bin/env ruby
#===============================================================================
# rxdata_build.rb IR_JSON
#-------------------------------------------------------------------------------
# Back end of the Tiled compiler (tiled_compiler.py build). Reads the
# intermediate JSON the Python side produced from src/tiled, evaluates the event
# .rb files, and writes the RPG Maker XP data the engine loads:
#   MapInfos.rxdata, Map###.rxdata, Tilesets.rxdata, CommonEvents.rxdata,
#   System.rxdata and atmospheres.dat
# into ir["out_dir"]. Files are only rewritten when their bytes change.
#
# Show Picture / Move Picture coordinates are halved (HalveData) to match the
# 256x192 build, exactly like tools/scripts/halve_data.rb does for .rxdata.
#
# With ir["check_only"], nothing is written: the event files are only
# evaluated, to report errors (used by `tiled_compiler.py validate`).
#
# Nothing is written when any event script has an error.
#
# Prints a JSON report on stdout: {"written": [...], "errors": [{file, message}]}
#===============================================================================
require_relative "tiled_rmxp"

module RxdataBuild
  module_function

  # @param h [Hash] {"name", "volume", "pitch"}
  # @return [RPG::AudioFile]
  def audio(h)
    h ||= {}
    return RPG::AudioFile.new(h["name"] || "", h["volume"] || 100, h["pitch"] || 100)
  end

  # Builds a page from Tiled settings plus commands from the event file.
  # @param s [Hash] settings
  # @param list [Array<RPG::EventCommand>, nil]
  # @param route [RPG::MoveRoute, nil]
  # @return [RPG::Event::Page]
  def page(s, list, route)
    pg = RPG::Event::Page.new
    c = pg.condition
    c.switch1_valid = s["switch1"].to_i > 0
    c.switch1_id = c.switch1_valid ? s["switch1"] : 1
    c.switch2_valid = s["switch2"].to_i > 0
    c.switch2_id = c.switch2_valid ? s["switch2"] : 1
    c.variable_valid = s["variable"].to_i > 0
    c.variable_id = c.variable_valid ? s["variable"] : 1
    c.variable_value = c.variable_valid ? s["variable_value"].to_i : 0
    c.self_switch_valid = !s["self_switch"].to_s.empty?
    c.self_switch_ch = c.self_switch_valid ? s["self_switch"] : "A"
    g = pg.graphic
    g.tile_id = s["tile_id"].to_i
    g.character_name = s["character_name"].to_s
    g.character_hue = s["character_hue"].to_i
    g.direction = (s["direction"] || 2).to_i
    g.pattern = s["pattern"].to_i
    g.opacity = (s["opacity"] || 255).to_i
    g.blend_type = s["blend_type"].to_i
    pg.move_type = s["move_type"].to_i
    pg.move_speed = (s["move_speed"] || 3).to_i
    pg.move_frequency = (s["move_frequency"] || 3).to_i
    pg.walk_anime = s.fetch("walk_anime", true)
    pg.step_anime = s.fetch("step_anime", false)
    pg.direction_fix = s.fetch("direction_fix", false)
    pg.through = s.fetch("through", false)
    pg.always_on_top = s.fetch("always_on_top", false)
    pg.trigger = s["trigger"].to_i
    pg.move_route = route if route
    pg.list = (list || []) + [RPG::EventCommand.new]
    return pg
  end

  # Runs the compiler back end.
  # @param ir [Hash]
  # @return [Hash] report
  def build(ir)
    out = ir["out_dir"]
    check_only = ir["check_only"]
    halve = ir.fetch("halve_pictures", true)
    written = []
    errors = []
    map_ids = ir["map_ids"] || {}
    spawns = ir["spawns"] || {}
    resolver = lambda do |to, spawn|
      id = to.is_a?(Integer) ? to : map_ids[to.to_s]
      raise ArgumentError, "transfer: no map named #{to.inspect} in the registry" unless id
      return [id, nil, nil, nil] if spawn.nil?
      s = (spawns[id.to_s] || {})[spawn.to_s]
      raise ArgumentError, "transfer: map #{to.inspect} has no Spawn object named #{spawn.inspect}" unless s
      [id, s[0], s[1], RPGFactory::DIRECTION[s[2].to_i] || :retain]
    end
    run = lambda do |path, params = {}|
      begin
        TiledRmxp::Factory.new(resolver, params).run_file(path)
      rescue StandardError, ScriptError => e
        where = e.backtrace&.find { |l| l.start_with?(path) }
        line = where ? where.split(":")[1] : nil
        errors << { "file" => path, "line" => line, "message" => "#{e.class}: #{e.message.lines.first&.strip}",
                    "event" => params["_where"] }
        nil
      end
    end
    # Files are only written once everything compiled, so a broken event
    # script never leaves a map without its event in build/Data.
    pending = []
    save = lambda do |obj, name|
      pending << [obj, name] unless check_only
    end

    # Maps
    infos = {}
    (ir["mapinfos"] || {}).each do |id, h|
      info = RPG::MapInfo.new
      info.name = h["name"].to_s
      info.parent_id = h["parent_id"].to_i
      info.order = h["order"].to_i
      info.expanded = h["expanded"] ? true : false
      info.scroll_x = h["scroll_x"].to_i
      info.scroll_y = h["scroll_y"].to_i
      infos[id.to_i] = info
    end
    (ir["maps"] || {}).each do |id, m|
      map = RPG::Map.new(m["width"], m["height"])
      map.tileset_id = m["tileset_id"]
      map.autoplay_bgm = m["autoplay_bgm"] ? true : false
      map.bgm = audio(m["bgm"])
      map.autoplay_bgs = m["autoplay_bgs"] ? true : false
      map.bgs = audio(m["bgs"] || { "volume" => 80 })
      map.encounter_list = m["encounter_list"] || []
      map.encounter_step = m["encounter_step"] || 30
      table = Table.new(m["width"], m["height"], 3)
      table.data = m["data"]
      map.data = table
      map.events = {}
      (m["events"] || []).each do |e|
        factory = e["script"] ? run.call(e["script"], e["params"] || {}) : TiledRmxp::Factory.new
        next unless factory
        ev = RPG::Event.new(e["x"], e["y"])
        ev.id = e["id"]
        ev.name = e["name"].to_s
        settings = e["pages"] || []
        count = [settings.length, (factory.pages.keys.max || -1) + 1, 1].max
        ev.pages = (0...count).map do |i|
          if i >= settings.length
            errors << { "file" => e["script"], "message" => "page #{i} has commands but the Tiled object has no page_#{i}" }
          end
          page(settings[i] || {}, factory.pages[i], factory.routes[i])
        end
        ev.pages.each { |pg| HalveData.halve_command_list(pg.list) } if halve
        map.events[ev.id] = ev
      end
      save.call(map, format("Map%03d.rxdata", id.to_i))
    end
    save.call(infos, "MapInfos.rxdata") unless infos.empty?

    # Tilesets
    if ir["tilesets"]
      list = [nil]
      ir["tilesets"].each do |h|
        ts = RPG::Tileset.new
        %w[id name tileset_name autotile_names panorama_name panorama_hue fog_name fog_hue fog_opacity
           fog_blend_type fog_zoom fog_sx fog_sy battleback_name].each do |k|
          ts.send("#{k}=", h[k]) if h.key?(k)
        end
        size = h["passages"].length
        %w[passages priorities terrain_tags].each do |k|
          t = Table.new(size)
          t.data = h[k]
          ts.send("#{k}=", t)
        end
        list[ts.id] = ts
      end
      save.call(list, "Tilesets.rxdata")
    end

    # Common events
    if ir["common_events"]
      list = [nil]
      ir["common_events"].each do |c|
        f = run.call(c["path"])
        next unless f
        ce = f.common_event
        unless ce
          errors << { "file" => c["path"], "message" => "doesn't define a common(...) event" }
          next
        end
        HalveData.halve_command_list(ce.list) if halve
        list[ce.id] = ce
      end
      # The engine makes a Game_CommonEvent for every id up to the last one,
      # so fill the gaps with empty common events.
      (1...list.length).each do |i|
        next if list[i]
        list[i] = RPG::CommonEvent.new
        list[i].id = i
      end
      save.call(list, "CommonEvents.rxdata")
    end

    save.call(TiledRmxp.from_json_value(ir["system"]), "System.rxdata") if ir["system"]
    save.call(ir["atmospheres"], "atmospheres.dat") if ir["atmospheres"]
    if errors.empty?
      pending.each { |obj, name| written << name if TiledRmxp.dump_if_changed(obj, File.join(out, name)) }
    end
    return { "written" => written, "errors" => errors }
  end

  def main(args)
    if args.length != 1
      warn("Usage: ruby #{File.basename(__FILE__)} IR_JSON")
      return 2
    end
    ir = JSON.parse(File.read(args[0], encoding: "UTF-8"))
    report = build(ir)
    puts JSON.generate(report)
    return report["errors"].empty? ? 0 : 1
  end
end

exit(RxdataBuild.main(ARGV)) if $PROGRAM_NAME == __FILE__
