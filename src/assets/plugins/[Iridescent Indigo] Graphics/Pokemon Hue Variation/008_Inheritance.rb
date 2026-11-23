#================================================================================================
# Pokémon Iridescent Indigo Graphics/Pokemon Hue Variation - 008_Inheritance.rb
#================================================================================================

#==================================================================
# module HueGenetics (inheritance)
#==================================================================
# @brief How hue alleles pass from parents to offspring.
module HueGenetics
  module_function

  # @brief Possibly nudges an inherited allele, with a GraphicsSettings::HUE_MUTATION_CHANCE
  # percent chance of moving it by up to HUE_MUTATION_SIZE either way.
  # @param allele [Integer]
  # @return [Integer]
  def drift(allele)
    size = GraphicsSettings::HUE_MUTATION_SIZE.to_i
    return allele if size <= 0 || rand(100) >= GraphicsSettings::HUE_MUTATION_CHANCE
    amount = 1 + rand(size)
    return clamp_allele(allele + ((rand(2) == 0) ? -amount : amount))
  end

  # @brief The alleles of a child of two parents: one random allele from each, each of
  # which may drift a little.
  # @param mother [Pokemon]
  # @param father [Pokemon]
  # @return [Array<Integer>] Two alleles.
  def inherit(mother, father)
    return [drift(mother.hue_alleles.sample), drift(father.hue_alleles.sample)]
  end
end

#==================================================================
# module DayCare::EggGenerator
#==================================================================
# @brief Gives Day Care eggs alleles inherited from their parents.
# Wraps generate itself (rather than one of its inherit_ steps) so this works with any
# version of it, including the Generation 9 Pack's.
class DayCare
  module EggGenerator
    class << self
      alias __hue_generate generate unless method_defined?(:__hue_generate)

      # @brief Generates an egg from two parents, then sets its hue alleles.
      # @param mother [Pokemon]
      # @param father [Pokemon]
      # @return [Pokemon] The egg.
      def generate(mother, father)
        egg = __hue_generate(mother, father)
        egg.hue_alleles = HueGenetics.inherit(mother, father) if egg
        return egg
      end
    end
  end
end
