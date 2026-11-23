#================================================================================================
# Pokémon Iridescent Indigo Graphics/Pokemon Hue Variation - 011_Debug.rb
#================================================================================================

#==================================================================
# module HueDebug
#==================================================================
# @brief Text helpers for the "Set hue variation" debug option.
module HueDebug
  module_function

  # @brief Describes a Pokémon's hue genetics in one line.
  # @param pkmn [Pokemon]
  # @return [String]
  def summary(pkmn)
    a, b = pkmn.hue_alleles
    range = HueGenetics.range_for(pkmn.species, pkmn.form)
    return _INTL("Alleles {1}/{2}, gene {3}, shift {4}° (range {5} to {6}).",
                 a, b, pkmn.hue_gene.round, HueGenetics.signed_degrees_for(pkmn), range[0], range[1])
  end

  # @brief Asks for a new allele value.
  # @param screen [Object] The party/storage debug screen.
  # @param current [Integer]
  # @return [Integer]
  def choose_allele(screen, current)
    params = ChooseNumberParams.new
    params.setRange(HueGenetics::ALLELE_MIN, HueGenetics::ALLELE_MAX)
    params.setNegativesAllowed(true)
    params.setDefaultValue(current)
    return pbMessageChooseNumber(
      _INTL("Set the allele ({1} to {2}; 0 is normal colors).", HueGenetics::ALLELE_MIN, HueGenetics::ALLELE_MAX),
      params
    ) { screen.pbUpdate }
  end
end

MenuHandlers.add(:pokemon_debug_menu, :set_hue, {
  "name"   => _INTL("Set hue variation"),
  "parent" => :cosmetic,
  "effect" => proc { |pkmn, pkmnid, heldpoke, settingUpBattle, screen|
    cmd = 0
    loop do
      cmd = screen.pbShowCommands(HueDebug.summary(pkmn),
                                  [_INTL("Set allele 1"), _INTL("Set allele 2"),
                                   _INTL("Randomize alleles"), _INTL("Reset to personal ID")], cmd)
      break if cmd < 0
      alleles = pkmn.hue_alleles.clone
      case cmd
      when 0, 1   # Set allele
        alleles[cmd] = HueDebug.choose_allele(screen, alleles[cmd])
        pkmn.hue_alleles = alleles
      when 2   # Randomize
        pkmn.hue_alleles = [HueGenetics.random_allele, HueGenetics.random_allele]
      when 3   # Reset
        pkmn.hue_alleles = nil
      end
      screen.pbRefreshSingle(pkmnid)
    end
    next false
  }
})
