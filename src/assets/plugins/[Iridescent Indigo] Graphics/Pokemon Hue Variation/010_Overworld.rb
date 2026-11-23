#================================================================================================
# Pokémon Iridescent Indigo Graphics/Pokemon Hue Variation - 010_Overworld.rb
#================================================================================================
# The following Pokémon's overworld sprite uses its hue shift. Sprite_Character already
# draws characters with their character_hue (through RPG::Cache), so all that's needed is
# to set it.

#==================================================================
# class Game_FollowingPokemon
#==================================================================
# @brief Draws the following Pokémon with its hue shift.
class Game_FollowingPokemon < Game_Follower
  unless private_method_defined?(:__hue_apply_pokemon_settings)
    alias __hue_apply_pokemon_settings apply_pokemon_settings
  end

  private

  # @brief Applies the shown Pokémon's settings, including its hue shift. Called whenever
  # the Pokémon changes and after the event's page is refreshed (which resets the hue).
  def apply_pokemon_settings
    __hue_apply_pokemon_settings
    @character_hue = HueVariation.hue_for(@pokemon)
  end
end

#==================================================================
# module FollowingPokemon
#==================================================================
# @brief Refreshes the following Pokémon's sprite when its hue shift changes
# (e.g. its alleles were edited in the debug menu).
module FollowingPokemon
  class << self
    alias __hue_signature signature unless method_defined?(:__hue_signature)

    # @brief What a Pokémon looks like as a follower, including its hue shift.
    # @param pkmn [Pokemon, nil]
    # @return [Array, nil]
    def signature(pkmn)
      ret = __hue_signature(pkmn)
      ret&.push(HueVariation.hue_for(pkmn))
      return ret
    end
  end
end
