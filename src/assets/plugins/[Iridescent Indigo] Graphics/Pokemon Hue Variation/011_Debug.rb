#================================================================================================
# Pokémon Iridescent Indigo Graphics/Pokemon Hue Variation - 011_Debug.rb
#================================================================================================

#==================================================================
# module HueDebug
#==================================================================
# @brief Text helpers for the "Set color variation" debug option.
module HueDebug
  module_function

  # @brief The display name of a color trait.
  # @param trait [Symbol] :hue, :saturation or :brightness.
  # @return [String]
  def trait_name(trait)
    case trait
    when :saturation then return _INTL("Saturation")
    when :brightness then return _INTL("Brightness")
    end
    return _INTL("Hue")
  end

  # @brief Describes one of a Pokémon's color genes in one line.
  # @param pkmn [Pokemon]
  # @param trait [Symbol]
  # @return [String]
  def summary(pkmn, trait = :hue)
    a, b = pkmn.color_alleles(trait)
    range = HueGenetics.range_for(pkmn.species, pkmn.form, trait)
    amount = (trait == :hue) ? HueGenetics.signed_degrees_for(pkmn) : HueGenetics.amount_for(pkmn, trait)
    unit = (trait == :hue) ? "°" : "%"
    return _INTL("{1}: alleles {2}/{3}, gene {4}, change {5}{6} (range {7} to {8}).",
                 trait_name(trait), a, b, HueGenetics.gene_for(pkmn, trait).round, amount, unit,
                 range[0], range[1])
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

  # @brief Lets the debug user edit one color gene of a Pokémon.
  # @param pkmn [Pokemon]
  # @param pkmnid [Object] The Pokémon's position, for refreshing the screen.
  # @param screen [Object] The party/storage debug screen.
  # @param trait [Symbol]
  def edit_trait(pkmn, pkmnid, screen, trait)
    cmd = 0
    loop do
      cmd = screen.pbShowCommands(summary(pkmn, trait),
                                  [_INTL("Set allele 1"), _INTL("Set allele 2"),
                                   _INTL("Randomize alleles"), _INTL("Reset to personal ID")], cmd)
      break if cmd < 0
      alleles = pkmn.color_alleles(trait).clone
      case cmd
      when 0, 1   # Set allele
        alleles[cmd] = choose_allele(screen, alleles[cmd])
        pkmn.set_color_alleles(trait, alleles)
      when 2   # Randomize
        pkmn.set_color_alleles(trait, [HueGenetics.random_allele, HueGenetics.random_allele])
      when 3   # Reset
        pkmn.set_color_alleles(trait, nil)
      end
      screen.pbRefreshSingle(pkmnid)
    end
  end
end

MenuHandlers.add(:pokemon_debug_menu, :set_hue, {
  "name"   => _INTL("Set color variation"),
  "parent" => :cosmetic,
  "effect" => proc { |pkmn, pkmnid, heldpoke, settingUpBattle, screen|
    traits = HueGenetics::TRAITS.keys
    cmd = 0
    loop do
      cmd = screen.pbShowCommands(_INTL("Which color gene?"),
                                  traits.map { |trait| HueDebug.trait_name(trait) }, cmd)
      break if cmd < 0
      HueDebug.edit_trait(pkmn, pkmnid, screen, traits[cmd])
    end
    next false
  }
})
