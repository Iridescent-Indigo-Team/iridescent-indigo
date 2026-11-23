#!/usr/bin/env ruby
#===============================================================================
# roundtrip_check.rb ORIGINAL_DATA_DIR COMPILED_DATA_DIR
#-------------------------------------------------------------------------------
# Checks that importing RPG Maker XP data into Tiled and compiling it back
# loses nothing the game uses. Used by the tests (make test-tiled) and handy
# after `make import-rxdata` (see docs/TILED.md).
#
# Compares:
#   * MapInfos (names, parents, order);
#   * every map's size, music and events (pages, conditions, graphics,
#     commands, move routes);
#   * every tile, by what it shows: the graphic (tileset image or autotile
#     name) and the tile within it, since tile ids are renumbered when
#     tilesets are combined;
#   * the passage, priority and terrain tag of every tile used;
#   * common events (by id) and System.
# Prints one line per difference and a JSON summary as the last line.
#===============================================================================
require_relative "tiled_rmxp"

module RoundtripCheck
  module_function

  # What a tile id shows in a tileset: [graphic, index] (nil for no tile).
  def tile_key(id, tileset)
    return nil if id == 0
    return [:invalid, id] if id < 48
    if id < 384
      return [:auto, TiledRmxp.utf8(tileset.autotile_names[(id / 48) - 1].to_s), id % 48]
    end
    return [:tile, TiledRmxp.utf8(tileset.tileset_name.to_s), id - 384]
  end

  def tile_props(id, tileset)
    return nil if id == 0
    return [tileset.passages[id], tileset.priorities[id], tileset.terrain_tags[id]]
  end

  def main(args)
    orig_dir, new_dir = args
    diffs = []
    diff = lambda { |msg| diffs << msg; puts(msg) if diffs.length <= 50 }
    o_infos = TiledRmxp.load(File.join(orig_dir, "MapInfos.rxdata"))
    n_infos = TiledRmxp.load(File.join(new_dir, "MapInfos.rxdata"))
    o_infos.each do |id, info|
      next unless File.file?(File.join(orig_dir, format("Map%03d.rxdata", id)))
      other = n_infos[id]
      if !other
        diff.call("map #{id}: missing from MapInfos")
      elsif TiledRmxp.norm(info) != TiledRmxp.norm(other)
        diff.call("map #{id}: MapInfos differ")
      end
    end
    o_tilesets = TiledRmxp.load(File.join(orig_dir, "Tilesets.rxdata"))
    n_tilesets = TiledRmxp.load(File.join(new_dir, "Tilesets.rxdata"))
    tiles = 0
    events = 0
    o_infos.keys.sort.each do |id|
      path = format("Map%03d.rxdata", id)
      next unless File.file?(File.join(orig_dir, path))
      unless File.file?(File.join(new_dir, path))
        diff.call("map #{id}: not compiled")
        next
      end
      om = TiledRmxp.load(File.join(orig_dir, path))
      nm = TiledRmxp.load(File.join(new_dir, path))
      %w[width height autoplay_bgm autoplay_bgs encounter_step].each do |k|
        diff.call("map #{id}: #{k} differs") if om.send(k) != nm.send(k)
      end
      %w[bgm bgs].each do |k|
        diff.call("map #{id}: #{k} differs") if TiledRmxp.norm(om.send(k)) != TiledRmxp.norm(nm.send(k))
      end
      ots = o_tilesets[om.tileset_id]
      nts = n_tilesets[nm.tileset_id]
      if ots && nts && om.width == nm.width && om.height == nm.height
        bad = 0
        om.height.times do |y|
          om.width.times do |x|
            3.times do |z|
              a = om.data[x, y, z]
              b = nm.data[x, y, z]
              ka = tile_key(a, ots)
              ka = nil if ka && ka[0] == :invalid
              ka = nil if ka && ka[0] == :auto && ka[1].empty?
              kb = tile_key(b, nts)
              tiles += 1 if ka
              if ka != kb
                bad += 1
                diff.call("map #{id}: tile #{x},#{y},#{z} shows #{kb.inspect}, not #{ka.inspect}") if bad <= 3
              elsif ka && tile_props(a, ots) != tile_props(b, nts)
                bad += 1
                diff.call("map #{id}: tile #{x},#{y},#{z} data #{tile_props(b, nts).inspect}, not #{tile_props(a, ots).inspect}") if bad <= 3
              end
            end
          end
        end
        diff.call("map #{id}: #{bad} tiles differ") if bad > 3
      end
      om.events.each do |eid, ev|
        events += 1
        ne = nm.events[eid]
        unless ne
          diff.call("map #{id}: event #{eid} missing")
          next
        end
        if TiledRmxp.norm(ev) != TiledRmxp.norm(ne)
          diff.call("map #{id}: event #{eid} (#{TiledRmxp.utf8(ev.name)}) differs")
        end
      end
      diff.call("map #{id}: #{nm.events.length - om.events.length} extra events") if nm.events.length > om.events.length
    end
    o_ce = TiledRmxp.load(File.join(orig_dir, "CommonEvents.rxdata"))
    n_ce = TiledRmxp.load(File.join(new_dir, "CommonEvents.rxdata"))
    o_ce.each do |ce|
      next unless ce
      other = n_ce[ce.id]
      if !other || TiledRmxp.norm(ce) != TiledRmxp.norm(other)
        diff.call("common event #{ce.id} differs")
      end
    end
    o_sys = TiledRmxp.load(File.join(orig_dir, "System.rxdata"))
    n_sys = TiledRmxp.load(File.join(new_dir, "System.rxdata"))
    diff.call("System differs") if TiledRmxp.norm(o_sys) != TiledRmxp.norm(n_sys)
    puts JSON.generate({ "differences" => diffs.length, "tiles" => tiles, "events" => events })
    return diffs.empty? ? 0 : 1
  end
end

exit(RoundtripCheck.main(ARGV)) if $PROGRAM_NAME == __FILE__
