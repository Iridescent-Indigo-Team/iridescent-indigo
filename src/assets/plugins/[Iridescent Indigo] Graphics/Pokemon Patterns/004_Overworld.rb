#================================================================================================
# Pokémon Iridescent Indigo Graphics/Pokemon Patterns - 004_Overworld.rb
#================================================================================================
# The following Pokémon uses its pattern's overworld sprite, from
# Graphics/Characters/Patterns/<PATTERN>/Followers[ shiny]/, if there is one.

#==================================================================
# module FollowingPokemon
#==================================================================
# @brief Pattern sprites and refreshing for the following Pokémon.
module FollowingPokemon
  class << self
    alias __pattern_sprite_name sprite_name unless method_defined?(:__pattern_sprite_name)
    alias __pattern_signature signature unless method_defined?(:__pattern_signature)

    # @brief The overworld sprite of a Pokémon: its pattern's sprite if there is one,
    # otherwise the normal sprite. Also used when preloading follower sprites.
    # @param pkmn [Pokemon, nil]
    # @return [String, nil] A file name in Graphics/Characters, e.g.
    # "Patterns/SPOTTED/Followers/BULBASAUR".
    def sprite_name(pkmn)
      pattern = PatternData.shown_pattern(pkmn)
      if pattern
        path = PatternSprites.resolve("Graphics/Characters/", SPRITE_FOLDER, pkmn.species, pkmn.form,
                                      pkmn.gender, pkmn.shiny?, false, pattern)
        return path.sub(/\A.*?Graphics\/Characters\//i, "").sub(/\.(png|gif)\z/i, "") if path
      end
      return __pattern_sprite_name(pkmn)
    end

    # @brief What a Pokémon looks like as a follower, including its pattern, so the sprite
    # changes when the pattern does (e.g. in the debug menu).
    # @param pkmn [Pokemon, nil]
    # @return [Array, nil]
    def signature(pkmn)
      ret = __pattern_signature(pkmn)
      ret&.push(PatternData.shown_pattern(pkmn))
      return ret
    end
  end
end
