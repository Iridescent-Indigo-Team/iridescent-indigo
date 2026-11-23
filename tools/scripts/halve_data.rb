#!/usr/bin/env ruby
#===============================================================================
# halve_data.rb SRC_DIR OUT_DIR [--skip-list FILE]
#-------------------------------------------------------------------------------
# Copies RMXP data files (*.rxdata) from SRC_DIR to OUT_DIR and halves the
# pixel values stored in them, from Essentials' 2x (512x384) scale to the
# game's 1x (256x192) scale. Pokessentials keeps its sources at 1x, so this
# runs when data comes in, not on every build:
#   * install_assets.sh halves Essentials' Data/ before copying it into
#     src/assets/data;
#   * downscale_assets.py (`make downscale-assets`) converts a src/assets/data
#     installed by older versions, which stored the 2x values.
# Data from another RMXP project made for Essentials' 2x graphics needs the
# same treatment before it goes into src/assets/data or is imported into
# Tiled.
#
# What is halved:
#   * Map*.rxdata, CommonEvents.rxdata, Troops.rxdata
#       Show Picture (231) and Move Picture (232) commands that use constant
#       coordinates: x and y are halved.
#   * Animations.rxdata (RMXP animations)
#       Every cell's x and y are halved.
#   * PkmnAnimations.rxdata (Essentials battle animations)
#       Every cell's x and y, and every timing's background x and y, are
#       halved.
# Every other file is copied unchanged. A file is only processed again when
# its source is newer than its output.
#
# Tile-based values (event positions, move routes, map scrolling) are not
# pixels and are left alone. Script calls inside events (code 355) can't be
# converted automatically.
#
# --skip-list FILE: skip files whose names match a regular expression listed
# (one per line) in FILE.
#===============================================================================
require "fileutils"

ROOT = File.expand_path("../..", __dir__)
require File.join(ROOT, "lib/eevee/rmxp/rgss_internal")
require File.join(ROOT, "lib/eevee/rmxp/rgss_rpg")

#===============================================================================
# Minimal copies of the Essentials classes stored in PkmnAnimations.rxdata, so
# Marshal can load and dump them. Only their instance variables matter here.
#===============================================================================
class PBAnimTiming; end
class PBAnimations < Array; end
class PBAnimation < Array; end

module HalveData
  # Indices of x and y in an Essentials animation cell (AnimFrame::X/Y).
  CELL_X = 0
  CELL_Y = 1
  # Event command codes with pixel coordinates.
  SHOW_PICTURE = 231
  MOVE_PICTURE = 232
  # Event command list files.
  EVENT_FILES = /\A(Map\d+|CommonEvents|Troops)\.rxdata\z/i

  module_function

  # Halves a pixel value, rounding halves away from zero.
  # @param value [Numeric, nil]
  # @return [Numeric, nil]
  def half(value)
    return value unless value.is_a?(Numeric)
    return (value / 2.0).round
  end

  # Halves a signed 16-bit value stored in an RMXP Table.
  # @param raw [Integer] unsigned 16-bit value
  # @return [Integer]
  def half_s16(raw)
    signed = (raw >= 0x8000) ? raw - 0x10000 : raw
    return half(signed) & 0xFFFF
  end

  # Halves picture coordinates in one list of event commands.
  # @param list [Array<RPG::EventCommand>, nil]
  # @return [Integer] number of commands changed
  def halve_command_list(list)
    return 0 unless list
    count = 0
    list.each do |command|
      next unless [SHOW_PICTURE, MOVE_PICTURE].include?(command.code)
      params = command.parameters
      next unless params[3] == 0   # 0 = constant coordinates, 1 = variables
      params[4] = half(params[4])
      params[5] = half(params[5])
      count += 1
    end
    return count
  end

  # Halves every event command list found in a loaded data object.
  # @return [Integer] number of commands changed
  def halve_events(data)
    count = 0
    case data
    when RPG::Map
      data.events.each_value do |event|
        event.pages.each { |page| count += halve_command_list(page.list) }
      end
    when Array
      data.each do |entry|
        next unless entry
        if entry.respond_to?(:pages)   # RPG::Troop
          entry.pages.each { |page| count += halve_command_list(page.list) }
        elsif entry.respond_to?(:list) # RPG::CommonEvent
          count += halve_command_list(entry.list)
        end
      end
    end
    return count
  end

  # Halves cell positions in RMXP animations.
  # @return [Integer] number of frames changed
  def halve_rmxp_animations(data)
    count = 0
    data.each do |anim|
      next unless anim
      anim.frames.each do |frame|
        table = frame.cell_data
        next if !table || table.xsize == 0
        table.xsize.times do |cell|
          table[cell, 1] = half_s16(table[cell, 1])
          table[cell, 2] = half_s16(table[cell, 2])
        end
        count += 1
      end
    end
    return count
  end

  # Halves cell positions and background offsets in Essentials animations.
  # @return [Integer] number of animations changed
  def halve_pk_animations(data)
    animations = data.instance_variable_get(:@array) || data
    count = 0
    animations.each do |anim|
      next unless anim
      (anim.instance_variable_get(:@array) || []).each do |frame|
        frame&.each do |cell|
          next unless cell
          cell[CELL_X] = half(cell[CELL_X])
          cell[CELL_Y] = half(cell[CELL_Y])
        end
      end
      (anim.instance_variable_get(:@timing) || []).each do |timing|
        %i[@bgX @bgY].each do |var|
          timing.instance_variable_set(var, half(timing.instance_variable_get(var)))
        end
      end
      count += 1
    end
    return count
  end

  # Converts one file, or copies it unchanged.
  # @return [String] a short description of what was done
  def convert(src, dst)
    name = File.basename(src)
    changed = nil
    if name =~ EVENT_FILES
      data = Marshal.load(File.binread(src))
      changed = "#{halve_events(data)} picture commands"
    elsif name.casecmp?("Animations.rxdata")
      data = Marshal.load(File.binread(src))
      changed = "#{halve_rmxp_animations(data)} animation frames"
    elsif name.casecmp?("PkmnAnimations.rxdata")
      data = Marshal.load(File.binread(src))
      changed = "#{halve_pk_animations(data)} battle animations"
    end
    FileUtils.mkdir_p(File.dirname(dst))
    if changed
      File.binwrite(dst + ".tmp", Marshal.dump(data))
      File.rename(dst + ".tmp", dst)
    else
      FileUtils.cp(src, dst)   # new mtime, so the file counts as up to date
    end
    return changed || "copied"
  end

  def main(args)
    skip = []
    if (i = args.index("--skip-list"))
      list = args[i + 1]
      args = args[0...i] + args[(i + 2)..]
      if list && File.file?(list)
        skip = File.readlines(list, chomp: true).reject(&:empty?).map { |l| Regexp.new("\\A#{l}\\z", Regexp::IGNORECASE) }
      end
    end
    if args.length != 2
      warn("Usage: ruby #{File.basename(__FILE__)} SRC_DIR OUT_DIR [--skip-list FILE]")
      return 2
    end
    src_dir, out_dir = args
    unless File.directory?(src_dir)
      warn("No game data found in #{src_dir}")
      return 0
    end
    stamp = File.mtime(__FILE__)
    processed = 0
    Dir.children(src_dir).sort.each do |name|
      src = File.join(src_dir, name)
      next if name.start_with?(".") || !File.file?(src)
      next if skip.any? { |re| re.match?(name) }
      dst = File.join(out_dir, name)
      if File.exist?(dst) && File.mtime(dst) >= File.mtime(src) && File.mtime(dst) >= stamp
        next
      end
      result = convert(src, dst)
      processed += 1
      puts("  #{name}: #{result}") if result != "copied" && ENV["VERBOSE"]
    end
    puts("Data: #{processed} files processed")
    return 0
  end
end

exit(HalveData.main(ARGV)) if $PROGRAM_NAME == __FILE__
