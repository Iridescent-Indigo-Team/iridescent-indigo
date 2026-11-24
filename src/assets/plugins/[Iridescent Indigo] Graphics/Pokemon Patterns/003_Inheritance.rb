#================================================================================================
# Pokémon Iridescent Indigo Graphics/Pokemon Patterns - 003_Inheritance.rb
#================================================================================================

#==================================================================
# module PatternData (inheritance)
#==================================================================
# @brief How an egg gets its pattern from its parents.
#
# Only a parent whose pattern exists in the egg's line can pass it on ("no pattern" counts),
# so Ditto, or a parent of another line, passes nothing. Then:
#   1. A parent holding an Everstone always passes its pattern (PATTERN_EVERSTONE_LOCK).
#   2. Otherwise there's a PATTERN_MUTATION_CHANCE% chance of a fresh roll, as for a wild
#      Pokémon. There's always a fresh roll if no parent can pass a pattern on.
#   3. Otherwise one parent's pattern is passed on, with odds in proportion to each
#      pattern's dominance (equal odds if both are 0).
module PatternData
  module_function

  # @brief The pattern an egg inherits.
  # @param egg [Pokemon]
  # @param mother [Pokemon]
  # @param father [Pokemon]
  # @param rng [Random, #rand]
  # @return [Symbol, nil] nil if the egg's line has no patterns.
  def inherit(egg, mother, father, rng = Random)
    species = egg.species
    return nil if !has_patterns?(species)
    eligible = [mother, father].compact.select { |parent| valid?(species, parent.pattern) }
    if GraphicsSettings::PATTERN_EVERSTONE_LOCK
      locked = eligible.select { |parent| parent.hasItem?(:EVERSTONE) }
      return locked[rng.rand(locked.length)].pattern if !locked.empty?
    end
    return roll(species, rng) if eligible.empty? || rng.rand(100) < GraphicsSettings::PATTERN_MUTATION_CHANCE
    weights = eligible.map { |parent| [dominance_for(species, parent.pattern), 0].max }
    weights = weights.map { 1 } if weights.sum <= 0
    pick = rng.rand(weights.sum)
    eligible.each_with_index do |parent, i|
      return parent.pattern if pick < weights[i]
      pick -= weights[i]
    end
    return eligible.last.pattern
  end
end

#==================================================================
# module DayCare::EggGenerator
#==================================================================
# @brief Gives Day Care eggs a pattern inherited from their parents.
# Wraps generate itself (like the hue variation's inheritance) so this works with any
# version of it, including the Generation 9 Pack's.
class DayCare
  module EggGenerator
    class << self
      alias __pattern_generate generate unless method_defined?(:__pattern_generate)

      # @brief Generates an egg from two parents, then sets its pattern.
      # @param mother [Pokemon]
      # @param father [Pokemon]
      # @return [Pokemon] The egg.
      def generate(mother, father)
        egg = __pattern_generate(mother, father)
        egg.pattern = PatternData.inherit(egg, mother, father) if egg
        return egg
      end
    end
  end
end
