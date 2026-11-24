#================================================================================================
# Pokémon Iridescent Indigo Graphics/Pokemon Hue Variation - 009_Sprites.rb
#================================================================================================
# Draws each Pokémon's battle, summary, party and storage graphics with its color changes.
# Recoloring is done by RPG::Cache: everywhere the engine passes a "hue" when loading a
# graphic (AnimatedBitmap.new(file, hue), IconSprite#setBitmap(file, hue), a character's
# character_hue), a ColorAdjust can be passed instead. RPG::Cache keeps one recolored copy
# per graphic and adjustment for as long as something is showing it.

#==================================================================
# module RPG::Cache
#==================================================================
# @brief Loads graphics recolored by a hue (Integer) or a ColorAdjust.
# Hue-only changes use the engine's own GPU path. Saturation/brightness changes, and any
# change to an animated GIF (which Bitmap#hue_change can't edit), are made by Recolor.
module RPG
  module Cache
    class << self
      alias __hue_load_bitmap load_bitmap unless method_defined?(:__hue_load_bitmap)

      # @brief Loads a graphic, recolored if hue isn't 0 / the identity adjustment.
      # @param folder_name [String]
      # @param filename [String]
      # @param hue [Integer, ColorAdjust]
      # @return [BitmapWrapper]
      def load_bitmap(folder_name, filename, hue = 0)
        # Most graphics have no hue at all, so skip straight to the engine's loader
        return __hue_load_bitmap(folder_name, filename, 0) if !hue.is_a?(ColorAdjust) && hue.to_i % 360 == 0
        adjust = (hue.is_a?(ColorAdjust)) ? hue : ColorAdjust.new(hue.to_i % 360)
        return __hue_load_bitmap(folder_name, filename, 0) if adjust.identity?
        base = __hue_load_bitmap(folder_name, filename, 0)   # Hold the original while working
        begin
          if Recolor.hue_only?(adjust) && !base.animated?
            return __hue_load_bitmap(folder_name, filename, adjust.hue % 360)
          end
          key = [pbLocalizedGraphic(folder_name + filename), adjust.key]
          ret = fromCache(key)
          if ret
            ret.addRef
          else
            ret = Recolor.recolored_copy(base, adjust)   # GifBitmap starts animated ones playing
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
# @brief Helpers for drawing individual Pokémon with their color changes.
module HueVariation
  module_function

  # @brief What to pass as the "hue" when loading a Pokémon's graphics.
  # @param pkmn [Pokemon, nil]
  # @return [Integer, ColorAdjust] 0 for no change, a hue in degrees for a hue-only change
  # (which keeps the engine's simple cache keys), otherwise a ColorAdjust.
  def adjust_for(pkmn)
    return 0 if !pkmn.is_a?(Pokemon)
    adjust = pkmn.color_adjust
    return 0 if adjust.identity?
    return adjust.hue % 360 if Recolor.hue_only?(adjust)
    return adjust
  end

  # @brief Whether a value from adjust_for changes anything.
  # @param adjust [Integer, ColorAdjust]
  # @return [Boolean]
  def changed?(adjust)
    return !adjust.identity? if adjust.is_a?(ColorAdjust)
    return adjust.to_i % 360 != 0
  end

  # @brief Loads a graphic as an AnimatedBitmap with color changes.
  # If the recolor fails for any reason, the graphic is loaded with its normal colors.
  # @param filename [String, nil]
  # @param adjust [Integer, ColorAdjust] From adjust_for.
  # @return [AnimatedBitmap, nil]
  def animated_bitmap(filename, adjust)
    return nil if !filename
    if changed?(adjust)
      ret = DevLog.guard("Could not recolor #{filename}") { AnimatedBitmap.new(filename, adjust) }
      return ret if ret
    end
    return AnimatedBitmap.new(filename)
  end
end

#==================================================================
# module GameData::Species
#==================================================================
# @brief Battle/summary sprites and icons of individual Pokémon use their color changes.
module GameData
  class Species
    # @brief A Pokémon's front or back sprite, recolored by its genes.
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
      ret = HueVariation.animated_bitmap(filename, HueVariation.adjust_for(pkmn))
      alter_bitmap_function = MultipleForms.getFunction(species, "alterBitmap")
      if ret && alter_bitmap_function
        new_ret = ret.copy
        ret.dispose
        new_ret.each { |bitmap| alter_bitmap_function.call(pkmn, bitmap) }
        ret = new_ret
      end
      return ret
    end

    # @brief A Pokémon's icon, recolored by its genes.
    # @param pkmn [Pokemon]
    # @return [Bitmap, nil]
    def self.icon_bitmap_from_pokemon(pkmn)
      return self.egg_icon_bitmap(pkmn.species, pkmn.form) if pkmn.egg?
      filename = self.icon_filename_from_pokemon(pkmn)
      return HueVariation.animated_bitmap(filename, HueVariation.adjust_for(pkmn))&.deanimate
    end
  end
end

#==================================================================
# class PokemonIconSprite
#==================================================================
# @brief Party, summary and battle-menu icons use the Pokémon's color changes.
class PokemonIconSprite < Sprite
  # @brief Shows a Pokémon's icon, recolored by its genes.
  # Mirrors the engine's version, but loads the recolored icon before sizing src_rect to
  # one frame. (Swapping in a different bitmap afterwards would reset src_rect to the whole
  # sheet, showing both frames at once.)
  # @param value [Pokemon, nil]
  def pokemon=(value)
    @pokemon = value
    @animBitmap&.dispose
    @animBitmap = nil
    if !@pokemon
      self.bitmap = nil
      @current_frame = 0
      return
    end
    filename = GameData::Species.icon_filename_from_pokemon(value)
    @animBitmap = HueVariation.animated_bitmap(filename, HueVariation.adjust_for(value))
    self.bitmap = @animBitmap.bitmap
    self.src_rect.width  = @animBitmap.height
    self.src_rect.height = @animBitmap.height
    @frames_count = @animBitmap.width / @animBitmap.height
    @current_frame = 0 if @current_frame >= @frames_count
    changeOrigin
  end
end

#==================================================================
# class PokemonBoxIcon
#==================================================================
# @brief PC storage icons use the Pokémon's color changes.
class PokemonBoxIcon < IconSprite
  # @brief Reloads the icon, recolored by the Pokémon's genes.
  def refresh
    return if !@pokemon
    filename = GameData::Species.icon_filename_from_pokemon(@pokemon)
    adjust = HueVariation.adjust_for(@pokemon)
    recolored = HueVariation.changed?(adjust) && DevLog.guard("Could not recolor storage icon") do
      self.setBitmap(filename, adjust)
      next true
    end
    self.setBitmap(filename) if !recolored
    self.src_rect = Rect.new(0, 0, self.bitmap.height, self.bitmap.height)
  end
end
