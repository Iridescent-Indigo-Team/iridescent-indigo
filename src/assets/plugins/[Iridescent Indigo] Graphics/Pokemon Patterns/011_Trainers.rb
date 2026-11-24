#================================================================================================
# Pokémon Iridescent Indigo Graphics/Pokemon Patterns - 011_Trainers.rb
#================================================================================================
# A trainer's Pokémon can be given a pattern in trainers.txt:
#
#   Pokemon = BULBASAUR,12
#       Pattern = SPOTTED
#
# (JSON: "pattern": "SPOTTED"; NONE for no pattern.) Pokémon without one roll a pattern
# seeded from the trainer's type, name and party slot (like their colors), so they look the
# same in every battle and rematch.

#==================================================================
# module PatternData (trainers)
#==================================================================
# @brief Patterns of trainers' Pokémon.
module PatternData
  # @brief Mixed into a trainer Pokémon's seed so its pattern doesn't follow its colors.
  TRAINER_SALT = 0x50415431   # "PAT1"

  module_function

  # @brief The pattern of one of a trainer's Pokémon.
  # @param pkmn [Pokemon] The generated Pokémon.
  # @param pkmn_data [Hash] Its entry in GameData::Trainer#pokemon.
  # @param trainer_type [Symbol]
  # @param real_name [String]
  # @param slot [Integer]
  # @return [Symbol, nil]
  def trainer_pattern(pkmn, pkmn_data, trainer_type, real_name, slot)
    return pkmn_data[:pattern] if pkmn_data[:pattern]
    seed = Zlib.crc32("#{trainer_type}|#{real_name}|#{slot}") ^ TRAINER_SALT
    return roll(pkmn.species, Random.new(seed))
  end

  # @brief Checks a trainer Pokémon's predefined pattern.
  # @param pkmn_data [Hash] The Pokémon's compiled PBS entry.
  # @return [String, nil] A description of the problem, or nil if it's valid.
  def trainer_pattern_error(pkmn_data)
    pattern = pkmn_data[:pattern]
    return nil if pattern.nil?
    species = pkmn_data[:species]
    if !has_patterns?(species)
      return _INTL("{1} has Pattern = {2}, but its evolution line has no patterns.", species, pattern)
    end
    return nil if valid?(species, pattern)
    return _INTL("Pattern {1} isn't defined for {2}'s line (its patterns are: {3}, or NONE).",
                 pattern, species, ids_for(species).join(", "))
  end
end

#==================================================================
# class GameData::Trainer
#==================================================================
# @brief Adds the Pattern key to trainers' Pokémon and sets each Pokémon's pattern.
module GameData
  class Trainer
    # Adding to SUB_SCHEMA itself also lets the PBS writer and the schema dump see the key
    SUB_SCHEMA["Pattern"] = [:pattern, "m"] if !SUB_SCHEMA.key?("Pattern")

    alias __pattern_to_trainer to_trainer unless method_defined?(:__pattern_to_trainer)

    # @brief Creates a battle-ready version of this trainer, with each Pokémon's pattern set
    # from the PBS data or the trainer's seed.
    # @return [NPCTrainer]
    def to_trainer
      trainer = __pattern_to_trainer
      trainer.party.each_with_index do |pkmn, slot|
        pkmn_data = @pokemon[slot]
        next if !pkmn || !pkmn_data
        pkmn.pattern = PatternData.trainer_pattern(pkmn, pkmn_data, @trainer_type, @real_name, slot)
      end
      return trainer
    end
  end
end

#==================================================================
# module Compiler
#==================================================================
# @brief Checks trainers' patterns when compiling trainers (patterns are compiled first).
module Compiler
  class << self
    unless method_defined?(:__pattern_validate_compiled_trainer)
      alias __pattern_validate_compiled_trainer validate_compiled_trainer
    end

    # @brief Validates a compiled trainer, including its Pokémon's patterns.
    # @param hash [Hash] The trainer's compiled data.
    def validate_compiled_trainer(hash)
      __pattern_validate_compiled_trainer(hash)
      hash[:pokemon].each do |pkmn|
        error = PatternData.trainer_pattern_error(pkmn)
        raise error + "\n" + FileLineData.linereport if error
      end
    end
  end
end

#==================================================================
# module TrainerPokemonProperty
#==================================================================
# @brief Keeps a trainer Pokémon's pattern when it's edited in the Debug menu's trainer
# editor, which only knows about its own fields and would otherwise drop it.
module TrainerPokemonProperty
  class << self
    alias __pattern_set set unless method_defined?(:__pattern_set)

    # @brief Edits a trainer's Pokémon, keeping its pattern.
    # @param settingname [String]
    # @param initsetting [Hash, nil] The Pokémon's current data.
    # @return [Hash, nil] The edited data, or nil if the Pokémon was removed.
    def set(settingname, initsetting)
      ret = __pattern_set(settingname, initsetting)
      ret[:pattern] = initsetting[:pattern] if ret && initsetting && initsetting[:pattern]
      return ret
    end
  end
end
