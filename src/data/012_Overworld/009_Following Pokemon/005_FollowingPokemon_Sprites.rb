#===============================================================================
# Following Pokémon: sprites.
#===============================================================================
module FollowingPokemon
  #=============================================================================
  # Keeps the overworld sprites of the party's Pokémon loaded, so that when the
  # lead Pokémon changes (or a map transfer clears RPG::Cache) its sprite
  # appears without a pause to load it. Sprites of Pokémon that leave the party
  # are released.
  #=============================================================================
  module SpriteCache
    # Folder the sprite names are in.
    FOLDER = "Graphics/Characters/"

    @bitmaps = {}

    module_function

    # @return [Array<String>] names of the loaded sprites
    def loaded
      return @bitmaps.keys
    end

    # The sprites that should be loaded: those of every party Pokémon that
    # could follow the player (any that isn't an egg, since fainted ones may be
    # revived).
    # @return [Array<String>]
    def wanted
      return [] if !$player
      names = $player.party.filter_map do |pkmn|
        next nil if !pkmn || pkmn.egg?
        next FollowingPokemon.sprite_name(pkmn)
      end
      return names.uniq
    end

    # Loads the sprites in wanted and releases any others.
    def update
      names = wanted
      (@bitmaps.keys - names).each { |name| release(name) }
      names.each { |name| preload(name) }
    end

    # Loads a sprite into RPG::Cache and keeps it there.
    # @param name [String] file name in Graphics/Characters
    def preload(name)
      return if @bitmaps[name] && !@bitmaps[name].disposed?
      bitmap = RPG::Cache.load_bitmap(FOLDER, name)
      bitmap.never_dispose = true if bitmap.respond_to?(:never_dispose=)
      @bitmaps[name] = bitmap
    rescue StandardError
      @bitmaps.delete(name)
    end

    # Stops keeping a sprite loaded.
    # @param name [String]
    def release(name)
      bitmap = @bitmaps.delete(name)
      return if !bitmap || bitmap.disposed?
      bitmap.never_dispose = false if bitmap.respond_to?(:never_dispose=)
      bitmap.dispose
    end

    # Releases every sprite.
    def clear
      @bitmaps.keys.each { |name| release(name) }
    end

    # Puts the loaded sprites back into RPG::Cache after it has been cleared
    # (which happens on every map transfer).
    def restore
      @bitmaps.each do |name, bitmap|
        next if bitmap.disposed?
        RPG::Cache.setKey(pbLocalizedGraphic(FOLDER + name), bitmap)
      end
    end
  end
end

#===============================================================================
# The following Pokémon is tinted by its status problem, on top of the usual
# day/night tint and screen tone.
#===============================================================================
class Sprite_Character
  alias __followingpokemon__update update unless method_defined?(:__followingpokemon__update)

  def update
    __followingpokemon__update
    return if disposed? || !@character.is_a?(Game_FollowingPokemon) || !self.visible
    # Only when the day/night tint was just reset (i.e. the sprite updated)
    return if !$scene.is_a?(Scene_Map) || !@character.should_update?
    status_tone = @character.status_tone
    return if !status_tone
    self.tone.set(self.tone.red + status_tone.red, self.tone.green + status_tone.green,
                  self.tone.blue + status_tone.blue, self.tone.gray + status_tone.gray)
  end
end

#===============================================================================
# Emote bubbles (animations shown at the "Top" position) sit on the following
# Pokémon's head rather than on the top of its sprite's frame, which for most
# Pokémon has a lot of empty space above them. Emotes rest at
# FollowingPokemon::EMOTE_OFFSET from there, whatever cell positions the emote
# animations in Animations.rxdata have.
#===============================================================================
class Sprite_Character
  # Name prefix of the following Pokémon's emote animations.
  EMOTE_ANIMATION_PREFIX = "Follower emote: "

  # How far to move an animation shown on this sprite. SpriteAnimation adds it
  # to the animation's position. Only "Top" animations on the following
  # Pokémon move; other characters' animations are where they always were.
  # @param animation [RPG::Animation, nil] the animation being shown
  # @param position [Integer] the animation's position (0 = Top)
  # @return [Array<Integer>] [x, y] in pixels
  def animation_offset(animation, position)
    return [0, 0] if position != 0 || !@character.is_a?(Game_FollowingPokemon)
    dx = 0
    dy = animation_top_inset
    if animation&.name&.start_with?(EMOTE_ANIMATION_PREFIX)
      rest = emote_rest_cell(animation)
      dx += FollowingPokemon::EMOTE_OFFSET[0] - rest[0]
      dy += FollowingPokemon::EMOTE_OFFSET[1] - rest[1]
    end
    return [dx, dy]
  end

  # Pixels of empty space at the top of the sprite's current frames, measured
  # across every frame of the direction it faces (so a bubble doesn't bob as it
  # walks).
  # @return [Integer]
  def animation_top_inset
    return 0 if !@character.is_a?(Game_FollowingPokemon) || @tile_id != 0
    bmp = self.bitmap
    return 0 if !bmp || bmp.disposed?
    rect = self.src_rect
    return 0 if rect.width <= 0 || rect.height <= 0
    key = [bmp.object_id, rect.y, rect.height]
    @animation_top_insets = {} if !@animation_top_insets || @animation_top_inset_bitmap != bmp
    @animation_top_inset_bitmap = bmp
    if !@animation_top_insets.has_key?(key)
      @animation_top_insets[key] = first_opaque_row(bmp, rect.y, rect.height)
    end
    return (@animation_top_insets[key] * self.zoom_y).round
  end

  private

  # The [x, y] of an emote animation's resting cell: the first cell of its last
  # frame (the bubble pops up and bounces before settling there).
  # @param animation [RPG::Animation]
  # @return [Array<Integer>]
  def emote_rest_cell(animation)
    @emote_rest_cells ||= {}
    key = [animation.object_id, animation.frame_max]
    return @emote_rest_cells[key] if @emote_rest_cells[key]
    ret = [0, 0]
    frame = animation.frames[animation.frame_max - 1]
    cells = frame&.cell_data
    if cells && cells.xsize > 0
      # Negative numbers may be stored as unsigned 16-bit values
      ret = [cells[0, 1], cells[0, 2]].map { |v| (v.to_i >= 0x8000) ? v.to_i - 0x10000 : v.to_i }
    end
    @emote_rest_cells[key] = ret
    return ret
  end

  # @param bmp [Bitmap]
  # @param top [Integer] y of the row of frames in bmp
  # @param height [Integer] height of the frames
  # @return [Integer] how many rows from top are fully transparent in every
  #   frame of the row (0 if none are opaque at all)
  def first_opaque_row(bmp, top, height)
    height.times do |row|
      y = top + row
      break if y >= bmp.height
      bmp.width.times do |x|
        return row if bmp.get_pixel(x, y).alpha > 0
      end
    end
    return 0
  end
end

#===============================================================================
# Keep the following Pokémon's preloaded sprites in RPG::Cache when it's
# cleared on a map transfer.
#===============================================================================
class Scene_Map
  alias __followingpokemon__createSpritesets createSpritesets unless method_defined?(:__followingpokemon__createSpritesets)

  def createSpritesets
    FollowingPokemon::SpriteCache.restore
    __followingpokemon__createSpritesets
  end
end
