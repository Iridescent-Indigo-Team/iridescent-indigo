#!/usr/bin/env ruby
#===============================================================================
# add_follower_animations.rb [FILE...]
#-------------------------------------------------------------------------------
# Adds the following Pokémon's animations to RMXP animation files
# (Animations.rxdata):
#   * "Follower ball out" / "Follower ball in": the Poké Ball the following
#     Pokémon comes out of and goes back into (Graphics/Animations/
#     Follower_ComeInOut.png).
#   * "Follower emote: NAME": the emote bubbles shown over the following
#     Pokémon (Graphics/Animations/Follower_Emote1.png and Follower_Emote2.png).
#
# Existing animations are never overwritten: new ones are appended after the
# last animation in the file. Running the script again updates the
# animations it added before (found by name) in place, so their IDs never
# change. The game finds these animations by name (see FollowingPokemon in
# src/data/012_Overworld/009_Following Pokemon), so their IDs don't matter.
#
# FILE defaults to lib/pokemon-essentials/Data/Animations.rxdata, plus
# src/assets/data/Animations.rxdata if it has been installed.
#
# Coordinates are at the 2x scale of the source graphics; `make data`
# (halve_data.rb) halves them for the build.
#===============================================================================
ROOT = File.expand_path("../..", __dir__)
require File.join(ROOT, "lib/eevee/rmxp/rgss_internal")
require File.join(ROOT, "lib/eevee/rmxp/rgss_rpg")

module FollowerAnimations
  # Every follower animation's name starts with this.
  PREFIX = "Follower "
  # RMXP animation positions.
  POSITION_TOP    = 0
  POSITION_BOTTOM = 2
  # Number of values per cell in a frame's cell_data table.
  CELL_VALUES = 8

  module_function

  # Builds one frame of an animation.
  # @param cells [Array<Array>] each [pattern, x, y, opacity]
  # @return [RPG::Animation::Frame]
  def frame(cells)
    ret = RPG::Animation::Frame.new
    ret.cell_max = cells.length
    table = Table.new(cells.length, CELL_VALUES)
    cells.each_with_index do |cell, i|
      pattern, x, y, opacity = cell
      # pattern, x, y, zoom %, angle, mirror, opacity, blend type. Negative
      # numbers are stored as unsigned 16-bit values, as RMXP does.
      [pattern, x, y, 100, 0, 0, opacity || 255, 0].each_with_index do |value, j|
        table[i, j] = value & 0xFFFF
      end
    end
    ret.cell_data = table
    return ret
  end

  # Builds a sound effect timing.
  # @param frame_index [Integer]
  # @param se_name [String]
  # @param volume [Integer]
  # @return [RPG::Animation::Timing]
  def timing(frame_index, se_name, volume = 80)
    ret = RPG::Animation::Timing.new
    ret.frame = frame_index
    ret.se = RPG::AudioFile.new(se_name, volume, 100)
    return ret
  end

  # @param name [String]
  # @param sheet [String] file in Graphics/Animations
  # @param position [Integer]
  # @param frames [Array<Array<Array>>] cells of each frame (see frame)
  # @param timings [Array<RPG::Animation::Timing>]
  # @return [RPG::Animation]
  def animation(name, sheet, position, frames, timings = [])
    ret = RPG::Animation.new
    ret.name           = name
    ret.animation_name = sheet
    ret.animation_hue  = 0
    ret.position       = position
    ret.frame_max      = frames.length
    ret.frames         = frames.map { |cells| frame(cells) }
    ret.timings        = timings
    return ret
  end

  # The Poké Ball opening and the Pokémon coming out of it. Follower_ComeInOut
  # cells 0-3 (top row) are the ball opening into a burst of sparkles.
  def ball_out
    y = -32
    patterns = [0, 0, 0, 1, 1, 2, 2, 3, 3]
    frames = patterns.map { |pattern| [[pattern, 0, y]] }
    return animation(PREFIX + "ball out", "Follower_ComeInOut", POSITION_BOTTOM,
                     frames, [timing(0, "Battle recall", 60)])
  end

  # The Pokémon going back into its Poké Ball. Follower_ComeInOut cells 5-7
  # (bottom row) are a puff of smoke shrinking into the ball.
  def ball_in
    y = -32
    patterns = [5, 5, 6, 6, 7, 7, 0, 0, 0]
    frames = patterns.map { |pattern| [[pattern, 0, y]] }
    return animation(PREFIX + "ball in", "Follower_ComeInOut", POSITION_BOTTOM,
                     frames, [timing(0, "Battle jump to ball", 60)])
  end

  # The emote bubbles: [name, sheet, first cell, second cell]. Each bubble has
  # two cells that the animation alternates between.
  EMOTES = [
    ["music",    "Follower_Emote1", 0, 5],
    ["happy",    "Follower_Emote1", 1, 2],
    ["smile",    "Follower_Emote1", 3, 4],
    ["question", "Follower_Emote1", 6, 7],
    ["heart",    "Follower_Emote1", 8, 9],
    ["poison",   "Follower_Emote2", 0, 1],
    ["angry",    "Follower_Emote2", 2, 3],
    ["ellipsis", "Follower_Emote2", 4, 9],
    ["sad",      "Follower_Emote2", 5, 6],
    ["mad",      "Follower_Emote2", 7, 8]
  ]

  # An emote bubble that pops up above the Pokémon's head, bounces, alternates
  # between its two cells, then fades out.
  #
  # The bubble is drawn 6px left of its cell's centre, with its tail tip 1px
  # above it. The animation is at the "Top" position, which the game puts on
  # the top of the Pokémon itself (not of its sprite's frame), so a cell at
  # (BUBBLE_X, REST_Y) centres the bubble with its tail just above the head.
  # These match FollowingPokemon::EMOTE_OFFSET (at half scale), and the game
  # moves the resting cell there anyway (see Sprite_Character#animation_offset),
  # so only the pop-up motion relative to REST_Y matters.
  BUBBLE_X = 6
  REST_Y   = -2

  def emote(name, sheet, cell_a, cell_b)
    frames = []
    # Pop up with a small bounce: y offsets from the resting position
    [[16, 128], [6, 200], [-6, 255], [-2, 255], [0, 255]].each do |dy, opacity|
      frames.push([[cell_a, BUBBLE_X, REST_Y + dy, opacity]])
    end
    # Alternate between the two cells
    16.times { |i| frames.push([[((i / 4).even?) ? cell_b : cell_a, BUBBLE_X, REST_Y]]) }
    # Fade out
    [170, 85].each { |opacity| frames.push([[cell_a, BUBBLE_X, REST_Y, opacity]]) }
    return animation(PREFIX + "emote: " + name, sheet, POSITION_TOP, frames,
                     [timing(0, "Exclaim", 60)])
  end

  # @return [Array<RPG::Animation>] every follower animation, in ID order
  def all
    return [ball_out, ball_in] + EMOTES.map { |args| emote(*args) }
  end

  # Adds/updates the follower animations in data (an array of animations,
  # indexed by ID, with nil at 0).
  # @return [Hash{String => Integer}] each animation's name and ID
  def merge(data)
    ret = {}
    all.each do |anim|
      id = data.index { |existing| existing&.name == anim.name }
      if !id
        id = data.length
        data.push(nil)
      end
      anim.id = id
      data[id] = anim
      ret[anim.name] = id
    end
    return ret
  end

  # Adds the follower animations to one file.
  # @param path [String]
  def process(path)
    data = Marshal.load(File.binread(path))
    before = Marshal.dump(data)
    ids = merge(data)
    after = Marshal.dump(data)
    if after == before
      puts "#{path}: up to date"
    else
      File.binwrite(path + ".tmp", after)
      File.rename(path + ".tmp", path)
      puts "#{path}: written"
    end
    ids.each { |name, id| puts format("  %3d  %s", id, name) }
  end
end

if $PROGRAM_NAME == __FILE__
  files = ARGV.dup
  if files.empty?
    files.push(File.join(ROOT, "lib/pokemon-essentials/Data/Animations.rxdata"))
    installed = File.join(ROOT, "src/assets/data/Animations.rxdata")
    files.push(installed) if File.exist?(installed)
  end
  files.each { |path| FollowerAnimations.process(path) }
end
