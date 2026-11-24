#================================================================================================
# Pokémon Iridescent Indigo Graphics/Pokemon Hue Variation - 013_Trainers.rb
#================================================================================================
# Trainers' Pokémon get the same colors in every battle. Without this, each load of a
# trainer creates Pokémon with new random personal IDs, so a rematch (or even retrying a
# battle) would show different colors.
#
# By default the alleles are seeded from the trainer's type, PBS name and party slot. The
# trainer's version (rematch tier) and the Pokémon's species are left out on purpose, so
# rematches keep their colors, and a Pokémon that has evolved between rematches keeps its
# colors too. Any gene can instead be set in the trainer PBS data with HueAlleles,
# SaturationAlleles or BrightnessAlleles (see docs/HUE_VARIATION.md).

#==================================================================
# module HueGenetics (trainers)
#==================================================================
# @brief Seeds and PBS keys for trainers' Pokémon.
module HueGenetics
  # @brief The trainer PBS key and data property for each trait.
  TRAINER_KEYS = {
    hue:        ["HueAlleles",        :hue_alleles],
    saturation: ["SaturationAlleles", :saturation_alleles],
    brightness: ["BrightnessAlleles", :brightness_alleles]
  }.freeze

  module_function

  # @brief A seed for one of a trainer's Pokémon that's the same every time it's loaded.
  # @param trainer_type [Symbol]
  # @param real_name [String] The trainer's name as written in the PBS data.
  # @param slot [Integer] The Pokémon's position in the party (0 for the first).
  # @return [Integer] A 32-bit seed, for alleles_from_personal_id.
  def trainer_seed(trainer_type, real_name, slot)
    return Zlib.crc32("#{trainer_type}|#{real_name}|#{slot}")
  end

  # @brief The alleles a trainer's Pokémon has for a trait: from the PBS data if set there,
  # otherwise from the trainer's seed.
  # @param pkmn_data [Hash] The Pokémon's entry in GameData::Trainer#pokemon.
  # @param trainer_type [Symbol]
  # @param real_name [String]
  # @param slot [Integer]
  # @param trait [Symbol] :hue, :saturation or :brightness.
  # @return [Array<Integer>] Two alleles.
  def trainer_alleles(pkmn_data, trainer_type, real_name, slot, trait)
    predefined = pkmn_data[TRAINER_KEYS[trait][1]]
    return normalize(predefined) if predefined && !Array(predefined).empty?
    return alleles_from_personal_id(trainer_seed(trainer_type, real_name, slot), trait)
  end

  # @brief Checks one trainer Pokémon's predefined alleles.
  # @param pkmn_data [Hash] The Pokémon's compiled PBS entry.
  # @return [String, nil] A description of the first problem, or nil if they're all valid.
  def trainer_allele_error(pkmn_data)
    TRAINER_KEYS.each_value do |pbs_key, property|
      value = pkmn_data[property]
      next if value.nil?
      if !value.is_a?(Array) || value.length != 2 || !value.all? { |v| v.is_a?(Integer) }
        return _INTL("{1} must be two whole numbers, e.g. {1} = -40,60.", pbs_key)
      end
      if !value.all? { |v| v.between?(ALLELE_MIN, ALLELE_MAX) }
        return _INTL("{1} values must be {2} to {3} (got {4}).", pbs_key, ALLELE_MIN, ALLELE_MAX, value.join(","))
      end
    end
    return nil
  end
end

#==================================================================
# class GameData::Trainer
#==================================================================
# @brief Adds the color allele keys to trainers' Pokémon, and sets every trainer Pokémon's
# alleles when the trainer is loaded.
module GameData
  class Trainer
    # Adding to SUB_SCHEMA itself (rather than overriding sub_schema) also lets the PBS
    # writer and the schema dump for the JSON tools see the new keys
    HueGenetics::TRAINER_KEYS.each_value do |pbs_key, property|
      SUB_SCHEMA[pbs_key] = [property, "*i"] if !SUB_SCHEMA.key?(pbs_key)
    end

    alias __hue_to_trainer to_trainer unless method_defined?(:__hue_to_trainer)

    # @brief Creates a battle-ready version of this trainer, with each Pokémon's colors set
    # from the PBS data or the trainer's seed.
    # @return [NPCTrainer]
    def to_trainer
      trainer = __hue_to_trainer
      trainer.party.each_with_index do |pkmn, slot|
        pkmn_data = @pokemon[slot]
        next if !pkmn || !pkmn_data
        HueGenetics::TRAITS.each_key do |trait|
          pkmn.set_color_alleles(trait, HueGenetics.trainer_alleles(pkmn_data, @trainer_type, @real_name,
                                                                    slot, trait))
        end
      end
      return trainer
    end
  end
end

#==================================================================
# module Compiler
#==================================================================
# @brief Checks predefined color alleles when compiling trainers.
module Compiler
  class << self
    unless method_defined?(:__hue_validate_compiled_trainer)
      alias __hue_validate_compiled_trainer validate_compiled_trainer
    end

    # @brief Validates a compiled trainer, including its Pokémon's color alleles.
    # @param hash [Hash] The trainer's compiled data.
    def validate_compiled_trainer(hash)
      __hue_validate_compiled_trainer(hash)
      hash[:pokemon].each do |pkmn|
        error = HueGenetics.trainer_allele_error(pkmn)
        raise error + "\n" + FileLineData.linereport if error
      end
    end
  end
end

#==================================================================
# module TrainerPokemonProperty
#==================================================================
# @brief Keeps a trainer Pokémon's color alleles when it's edited in the Debug menu's
# trainer editor, which only knows about its own fields and would otherwise drop them.
module TrainerPokemonProperty
  class << self
    alias __hue_set set unless method_defined?(:__hue_set)

    # @brief Edits a trainer's Pokémon, keeping its color alleles.
    # @param settingname [String]
    # @param initsetting [Hash, nil] The Pokémon's current data.
    # @return [Hash, nil] The edited data, or nil if the Pokémon was removed.
    def set(settingname, initsetting)
      ret = __hue_set(settingname, initsetting)
      if ret && initsetting
        HueGenetics::TRAINER_KEYS.each_value do |_pbs_key, property|
          ret[property] = initsetting[property] if initsetting[property]
        end
      end
      return ret
    end
  end
end
