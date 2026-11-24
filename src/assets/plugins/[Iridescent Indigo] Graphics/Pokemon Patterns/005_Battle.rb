#================================================================================================
# Pokémon Iridescent Indigo Graphics/Pokemon Patterns - 005_Battle.rb
#================================================================================================
# Battle sprites are loaded from the Pokémon object the scene is given, so patterns need no
# battle code of their own:
#   - Transform and Imposter call scene.pbChangePokemon(user, target.pokemon), so the user
#     is drawn with the target individual's pattern (and colors).
#   - Illusion sends out the Pokémon it disguises as (effects[PBEffects::Illusion]), so the
#     disguised-as Pokémon's pattern is shown until the Illusion breaks.
# This file only records the pattern a battler appears to have in the Pokédex.

#==================================================================
# class Battle
#==================================================================
# @brief Records seen patterns in the Pokédex.
class Battle
  alias __pattern_pbSetSeen pbSetSeen unless method_defined?(:__pattern_pbSetSeen)

  # @brief Registers a battler as seen, including the pattern it appears to have (under
  # Illusion, the disguised-as Pokémon's).
  # @param battler [Battle::Battler, Pokemon, nil]
  def pbSetSeen(battler)
    __pattern_pbSetSeen(battler)
    PatternDex.register_battler(self, battler)
  end
end

#==================================================================
# class SafariBattle
#==================================================================
# @brief Records seen patterns in Safari battles too.
class SafariBattle
  alias __pattern_pbSetSeen pbSetSeen unless method_defined?(:__pattern_pbSetSeen)

  # @brief Registers a battler as seen, including its pattern.
  # @param battler [Battle::Battler, Pokemon, nil]
  def pbSetSeen(battler)
    __pattern_pbSetSeen(battler)
    PatternDex.register_battler(self, battler)
  end
end
