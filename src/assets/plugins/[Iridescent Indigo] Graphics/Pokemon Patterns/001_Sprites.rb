#================================================================================================
# Pokémon Iridescent Indigo Graphics/Pokemon Patterns - 001_Sprites.rb
#================================================================================================
# Patterned Pokémon are drawn with whole sprites of their own (not overlays), found by
# hooking the sprite lookup. A pattern's sprites mirror the normal sprite folders:
#
#   Graphics/Pokemon/Patterns/SPOTTED/Front/BULBASAUR.png
#   Graphics/Pokemon/Patterns/SPOTTED/Front shiny/BULBASAUR.png
#   Graphics/Pokemon/Patterns/SPOTTED/Back/IVYSAUR_female.png
#   Graphics/Pokemon/Patterns/SPOTTED/Icons/VENUSAUR_1.png
#   Graphics/Characters/Patterns/SPOTTED/Followers/BULBASAUR.png
#
# Form and shininess must match exactly. Gender and shadow fall back the way the normal
# sprites do. If no pattern sprite fits, the normal sprite is used, silently. Hue variation
# is applied on top of whichever sprite is chosen.

#==================================================================
# module PatternSprites
#==================================================================
# @brief Finds pattern sprites.
module PatternSprites
  # @brief The folder (inside Graphics/Pokemon/ or Graphics/Characters/) holding one folder
  # per pattern id.
  FOLDER = "Patterns"

  @cache = {}

  class << self
    # @brief Forgets which pattern sprites were found (e.g. after adding sprites while the
    # game is running).
    def clear_cache
      @cache.clear
    end

    # @brief The pattern sprite to draw instead of a normal sprite.
    # @param root [String] "Graphics/Pokemon/" or "Graphics/Characters/".
    # @param subfolder [String] "Front", "Back", "Icons" or "Followers" (" shiny" is added for
    # shiny Pokémon).
    # @param species [Symbol]
    # @param form [Integer]
    # @param gender [Integer]
    # @param shiny [Boolean]
    # @param shadow [Boolean]
    # @param pattern [Symbol]
    # @return [String, nil] The file, or nil if there's no pattern sprite for this Pokémon.
    def resolve(root, subfolder, species, form, gender, shiny, shadow, pattern)
      return nil if !pattern || !species
      key = [root, subfolder, species, form || 0, gender, !!shiny, !!shadow, pattern]
      return @cache[key] if @cache.key?(key)
      @cache[key] = DevLog.guard("Could not look up the #{pattern} sprite of #{species}") do
        next find(root, subfolder, GameData::Species.get(species).species, form || 0, gender,
                  !!shiny, !!shadow, pattern)
      end
      return @cache[key]
    end

    private

    # @brief Looks for a pattern sprite on disk.
    # @return [String, nil]
    def find(root, subfolder, species, form, gender, shiny, shadow, pattern)
      dir = "#{root}#{FOLDER}/#{pattern}/#{subfolder}#{(shiny) ? ' shiny' : ''}/"
      forms = [(form > 0) ? "_#{form}" : ""]
      # A form without sprites of its own uses form 0's; its patterns can too
      forms.push("") if form > 0 && !base_uses_form?(root, subfolder, species, form, gender, shiny, shadow)
      genders = (gender == 1) ? ["_female", ""] : [""]
      shadows = (shadow) ? ["_shadow", ""] : [""]
      # Same preference order as GameData::Species.check_graphic_file
      shadows.each do |sh|
        genders.each do |g|
          forms.each do |f|
            ret = pbResolveBitmap("#{dir}#{species}#{f}#{g}#{sh}")
            return ret if ret
          end
        end
      end
      return nil
    end

    # @brief Whether the normal sprite of a form is drawn specially for that form.
    # @return [Boolean]
    def base_uses_form?(root, subfolder, species, form, gender, shiny, shadow)
      base = GameData::Species.check_graphic_file(root, species, form, gender, shiny, shadow, subfolder)
      return false if !base
      return File.basename(base, ".*").match?(/\A#{Regexp.escape(species.to_s)}_#{form}(_|\z)/)
    end
  end
end

#==================================================================
# module GameData::Species
#==================================================================
# @brief Battle, summary, storage and party graphics of individual Pokémon use their
# pattern's sprites. Graphics of a species rather than a Pokémon are unchanged.
module GameData
  class Species
    class << self
      unless method_defined?(:__pattern_sprite_filename_from_pokemon)
        alias __pattern_sprite_filename_from_pokemon sprite_filename_from_pokemon
      end
      unless method_defined?(:__pattern_icon_filename_from_pokemon)
        alias __pattern_icon_filename_from_pokemon icon_filename_from_pokemon
      end

      # @brief The file a Pokémon's front or back sprite is loaded from: its pattern's
      # sprite if there is one, otherwise the normal sprite.
      # @param pkmn [Pokemon]
      # @param back [Boolean]
      # @param species [Symbol, nil] Draw as this species instead (e.g. during evolution).
      # @return [String, nil]
      def sprite_filename_from_pokemon(pkmn, back = false, species = nil)
        species ||= pkmn.species
        pattern = PatternData.shown_pattern(pkmn, species)
        if pattern
          ret = PatternSprites.resolve("Graphics/Pokemon/", (back) ? "Back" : "Front", species, pkmn.form,
                                       pkmn.gender, pkmn.shiny?, pkmn.shadowPokemon?, pattern)
          return ret if ret
        end
        return __pattern_sprite_filename_from_pokemon(pkmn, back, species)
      end

      # @brief The file a Pokémon's icon is loaded from: its pattern's icon if there is one,
      # otherwise the normal icon.
      # @param pkmn [Pokemon]
      # @return [String, nil]
      def icon_filename_from_pokemon(pkmn)
        pattern = PatternData.shown_pattern(pkmn)
        if pattern
          ret = PatternSprites.resolve("Graphics/Pokemon/", "Icons", pkmn.species, pkmn.form, pkmn.gender,
                                       pkmn.shiny?, pkmn.shadowPokemon?, pattern)
          return ret if ret
        end
        return __pattern_icon_filename_from_pokemon(pkmn)
      end
    end
  end
end
