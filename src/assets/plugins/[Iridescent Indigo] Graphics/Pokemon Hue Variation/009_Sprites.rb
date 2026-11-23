#================================================================================================
# Pokémon Iridescent Indigo Graphics/Pokemon Hue Variation - 009_Sprites.rb
#================================================================================================
# Draws each Pokémon's battle, summary, party and storage graphics with its hue shift.
# Recoloring is done by RPG::Cache (AnimatedBitmap.new(file, hue)), which keeps one
# recolored copy per graphic and hue for as long as something is showing it.

#==================================================================
# module RPG::Cache
#==================================================================
# @brief Lets hue-shifted graphics be animated GIFs.
# The engine's Bitmap#hue_change can't change an animated bitmap, so those are recolored
# frame by frame into a new animated bitmap instead.
module RPG
  module Cache
    class << self
      alias __hue_load_bitmap load_bitmap unless method_defined?(:__hue_load_bitmap)

      # @brief Loads a graphic, recolored by hue degrees if hue isn't 0.
      # @param folder_name [String]
      # @param filename [String]
      # @param hue [Integer]
      # @return [BitmapWrapper]
      def load_bitmap(folder_name, filename, hue = 0)
        hue = hue.to_i % 360
        return __hue_load_bitmap(folder_name, filename, 0) if hue == 0
        base = __hue_load_bitmap(folder_name, filename, 0)   # Hold the original while working
        begin
          return __hue_load_bitmap(folder_name, filename, hue) if !base.animated?
          key = [pbLocalizedGraphic(folder_name + filename), hue]
          ret = fromCache(key)
          if ret
            ret.addRef
          else
            ret = Recolor.recolored_copy(base, ColorAdjust.new(hue))   # GifBitmap starts it playing
            setKey(key, ret)
          end
          return ret
        ensure
          base.dispose
        end
      end
    end
  end
end

#==================================================================
# module HueVariation
#==================================================================
# @brief Helpers for drawing individual Pokémon with their hue shift.
module HueVariation
  module_function

  # @brief The hue shift to draw a Pokémon with.
  # @param pkmn [Pokemon, nil]
  # @return [Integer] 0 to 359.
  def hue_for(pkmn)
    return 0 if !pkmn.is_a?(Pokemon)
    return pkmn.hue_shift
  end

  # @brief Loads a graphic as an AnimatedBitmap with a hue shift.
  # If the recolor fails for any reason, the graphic is loaded with its normal colors.
  # @param filename [String, nil]
  # @param hue [Integer]
  # @return [AnimatedBitmap, nil]
  def animated_bitmap(filename, hue)
    return nil if !filename
    if hue != 0
      ret = DevLog.guard("Could not recolor #{filename}") { AnimatedBitmap.new(filename, hue) }
      return ret if ret
    end
    return AnimatedBitmap.new(filename)
  end
end

#==================================================================
# module GameData::Species
#==================================================================
# @brief Battle/summary sprites and icons of individual Pokémon use their hue shift.
module GameData
  class Species
    # @brief A Pokémon's front or back sprite, recolored by its hue shift.
    # Mirrors the engine's version, including species' alterBitmap functions (e.g. Spinda).
    # @param pkmn [Pokemon]
    # @param back [Boolean]
    # @param species [Symbol, nil] Draw as this species instead (e.g. during evolution).
    # @return [AnimatedBitmap, nil]
    def self.sprite_bitmap_from_pokemon(pkmn, back = false, species = nil)
      species = pkmn.species if !species
      species = GameData::Species.get(species).species   # Just to be sure it's a symbol
      return self.egg_sprite_bitmap(species, pkmn.form) if pkmn.egg?
      if back
        filename = self.back_sprite_filename(species, pkmn.form, pkmn.gender, pkmn.shiny?, pkmn.shadowPokemon?)
      else
        filename = self.front_sprite_filename(species, pkmn.form, pkmn.gender, pkmn.shiny?, pkmn.shadowPokemon?)
      end
      ret = HueVariation.animated_bitmap(filename, HueVariation.hue_for(pkmn))
      alter_bitmap_function = MultipleForms.getFunction(species, "alterBitmap")
      if ret && alter_bitmap_function
        new_ret = ret.copy
        ret.dispose
        new_ret.each { |bitmap| alter_bitmap_function.call(pkmn, bitmap) }
        ret = new_ret
      end
      return ret
    end

    # @brief A Pokémon's icon, recolored by its hue shift.
    # @param pkmn [Pokemon]
    # @return [Bitmap, nil]
    def self.icon_bitmap_from_pokemon(pkmn)
      return self.egg_icon_bitmap(pkmn.species, pkmn.form) if pkmn.egg?
      filename = self.icon_filename_from_pokemon(pkmn)
      return HueVariation.animated_bitmap(filename, HueVariation.hue_for(pkmn))&.deanimate
    end
  end
end

#==================================================================
# class PokemonIconSprite
#==================================================================
# @brief Party, summary and battle-menu icons use the Pokémon's hue shift.
class PokemonIconSprite < Sprite
  alias __hue_pokemon_set pokemon= unless method_defined?(:__hue_pokemon_set)

  # @brief Shows a Pokémon's icon, recolored by its hue shift.
  # @param value [Pokemon, nil]
  def pokemon=(value)
    __hue_pokemon_set(value)
    hue = HueVariation.hue_for(value)
    return if hue == 0 || !@animBitmap
    recolored = DevLog.guard("Could not recolor icon") do
      AnimatedBitmap.new(GameData::Species.icon_filename_from_pokemon(value), hue)
    end
    return if !recolored
    @animBitmap.dispose
    @animBitmap = recolored
    self.bitmap = @animBitmap.bitmap
  end
end

#==================================================================
# class PokemonBoxIcon
#==================================================================
# @brief PC storage icons use the Pokémon's hue shift.
class PokemonBoxIcon < IconSprite
  # @brief Reloads the icon, recolored by the Pokémon's hue shift.
  def refresh
    return if !@pokemon
    filename = GameData::Species.icon_filename_from_pokemon(@pokemon)
    hue = HueVariation.hue_for(@pokemon)
    recolored = (hue != 0) && DevLog.guard("Could not recolor storage icon") do
      self.setBitmap(filename, hue)
      next true
    end
    self.setBitmap(filename) if !recolored
    self.src_rect = Rect.new(0, 0, self.bitmap.height, self.bitmap.height)
  end
end
