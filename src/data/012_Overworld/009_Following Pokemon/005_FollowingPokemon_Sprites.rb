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
