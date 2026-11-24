#================================================================================================
# Pokémon Iridescent Indigo Graphics/Pokemon Hue Variation - 010_Overworld.rb
#================================================================================================
# The following Pokémon's overworld sprite uses its color changes. Sprite_Character already
# draws characters with their character_hue (through RPG::Cache, which also accepts a
# ColorAdjust; see 009_Sprites.rb), so all that's needed is to set it.

#==================================================================
# class Game_FollowingPokemon
#==================================================================
# @brief Draws the following Pokémon with its color changes.
class Game_FollowingPokemon < Game_Follower
  unless private_method_defined?(:__hue_apply_pokemon_settings)
    alias __hue_apply_pokemon_settings apply_pokemon_settings
  end

  private

  # @brief Applies the shown Pokémon's settings, including its color changes. Called whenever
  # the Pokémon changes and after the event's page is refreshed (which resets character_hue).
  def apply_pokemon_settings
    __hue_apply_pokemon_settings
    @character_hue = HueVariation.adjust_for(@pokemon)
  end
end

#==================================================================
# module FollowingPokemon
#==================================================================
# @brief Refreshes the following Pokémon's sprite when its color changes (e.g. its alleles
# were edited in the debug menu, or the player changed the Color variation option).
module FollowingPokemon
  class << self
    alias __hue_signature signature unless method_defined?(:__hue_signature)

    # @brief What a Pokémon looks like as a follower, including its color changes.
    # @param pkmn [Pokemon, nil]
    # @return [Array, nil]
    def signature(pkmn)
      ret = __hue_signature(pkmn)
      # The signature is saved, so store a plain string rather than a ColorAdjust
      adjust = HueVariation.adjust_for(pkmn)
      ret&.push((adjust.is_a?(ColorAdjust)) ? adjust.key : adjust)
      return ret
    end
  end
end
