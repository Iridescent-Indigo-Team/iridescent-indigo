#================================================================================================
# Pokémon Iridescent Indigo Graphics/Pokemon Patterns - 012_Events.rb
#================================================================================================
# Script helpers for events:
#
#   pbAddPokemonWithPattern(:BULBASAUR, 5, :SPOTTED)   # Gift Pokémon with a pattern
#   pbSetNextWildPattern(:SPOTTED)                     # The next wild Pokémon has this pattern
#
# A pattern its line doesn't have is ignored (the Pokémon rolls one as usual).

#==================================================================
# class Game_Temp
#==================================================================
# @brief Holds the pattern for the next wild Pokémon.
class Game_Temp
  # @return [Symbol, nil] The pattern the next wild Pokémon is given (set by
  # pbSetNextWildPattern). Not saved.
  attr_accessor :next_wild_pattern
end

# @brief Gives the player a Pokémon with a pattern (see pbAddPokemon).
# @param species [Symbol]
# @param level [Integer]
# @param pattern [Symbol] A pattern of the species' line, or :NONE.
# @param see_form [Boolean] Whether to register it in the Pokédex.
# @return [Boolean] Whether it was added.
def pbAddPokemonWithPattern(species, level, pattern, see_form = true)
  pkmn = Pokemon.new(species, level)
  pkmn.pattern = pattern if PatternData.valid?(pkmn.species, pattern.to_s.upcase.to_sym)
  return pbAddPokemon(pkmn, level, see_form)
end

# @brief Gives the next wild Pokémon a pattern (only that one; the first one in a double
# battle). Cleared by passing nil.
# @param pattern [Symbol, nil]
def pbSetNextWildPattern(pattern)
  $game_temp.next_wild_pattern = (pattern.nil?) ? nil : pattern.to_s.upcase.to_sym
end

EventHandlers.add(:on_wild_pokemon_created, :set_next_wild_pattern,
  proc { |pkmn|
    pattern = $game_temp.next_wild_pattern
    next if !pattern
    $game_temp.next_wild_pattern = nil
    pkmn.pattern = pattern if PatternData.valid?(pkmn.species, pattern)
  }
)
