#================================================================================================
# Pokémon Iridescent Indigo Graphics/Pokemon Patterns - 003_Inheritance.rb
#================================================================================================

#==================================================================
# class Daycare::EggGenerator
#==================================================================
# @brief Logic for inheriting a pattern.
class << DayCare::EggGenerator
  alias __patterns_generate generate
  def generate(mother, father)
    egg = __patterns_generate(mother, father)
    egg.pattern = PatternData.inherit(egg, mother, father)
    egg
  end
end