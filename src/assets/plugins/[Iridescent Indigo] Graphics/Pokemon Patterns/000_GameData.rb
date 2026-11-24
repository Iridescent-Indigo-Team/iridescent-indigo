#================================================================================================
# Pokémon Iridescent Indigo Graphics/Pokemon Patterns - 000_GameData.rb
#================================================================================================
# The patterns of each evolution line, read from PBS/pokemon_patterns.txt. Each section is
# one evolution line, named after the line's first species (its baby species, ignoring
# incense), and lists the patterns any Pokémon of that line can have:
#
#   [BULBASAUR]
#   NoPatternWeight = 80
#   NoPatternDominance = 2
#   Pattern = SPOTTED,Spotted,15,1
#   Pattern = STRIPED,Striped,5,3
#
# Pattern = ID,Name,Weight[,Dominance]. See docs/POKEMON_PATTERNS.md.

#==================================================================
# module MessageTypes
#==================================================================
# @brief The message table holding pattern names, for translation.
module MessageTypes
  # @brief Pattern names (from pokemon_patterns.txt). Mirrored in
  # tools/importer/locales/locjson/messages.py.
  POKEMON_PATTERN_NAMES = 32 unless const_defined?(:POKEMON_PATTERN_NAMES)
end

#==================================================================
# class GameData::PokemonPattern
#==================================================================
# @brief The patterns of one evolution line.
module GameData
  class PokemonPattern
    # @return [Symbol] The line's first species (also the section name).
    attr_reader :id
    # @return [Integer, nil] Roll weight of "no pattern", as written in the PBS file.
    attr_reader :no_pattern_weight
    # @return [Integer, nil] Breeding dominance of "no pattern", as written in the PBS file.
    attr_reader :no_pattern_dominance
    # @return [Array<Array>] [id, real name, weight, dominance or nil] for each pattern, as
    # written in the PBS file.
    attr_reader :patterns
    # @return [String] The suffix of the PBS file this line came from.
    attr_reader :pbs_file_suffix

    DATA = {}
    DATA_FILENAME = "pokemon_patterns.dat"
    PBS_BASE_FILENAME = "pokemon_patterns"
    # The file doesn't have to exist; with no file, no species has patterns
    OPTIONAL = true

    SCHEMA = {
      "SectionName"        => [:id,                   "e", :Species],
      "NoPatternWeight"    => [:no_pattern_weight,    "u"],
      "NoPatternDominance" => [:no_pattern_dominance, "u"],
      "Pattern"            => [:patterns,             "^msvU"]
    }

    # @brief The id that means "rolled, but no pattern" (the normal sprites). It can't be
    # used as a pattern id.
    NONE = :NONE

    extend ClassMethodsSymbols
    include InstanceMethods

    singleton_class.alias_method(:__pattern_load, :load) unless singleton_class.method_defined?(:__pattern_load)

    # @brief Loads the compiled data, if there is any (the PBS file is optional).
    def self.load
      __pattern_load if FileTest.exist?("Data/#{self::DATA_FILENAME}")
    end

    # @param hash [Hash] The compiled section.
    def initialize(hash)
      @id                   = hash[:id]
      @no_pattern_weight    = hash[:no_pattern_weight]
      @no_pattern_dominance = hash[:no_pattern_dominance]
      @patterns             = hash[:patterns] || []
      @pbs_file_suffix      = hash[:pbs_file_suffix] || ""
    end

    # @return [Symbol] The line's first species.
    def species
      return @id
    end

    # @return [Array<Symbol>] The line's pattern ids, in the order they're defined.
    def pattern_ids
      return @patterns.map { |pattern| pattern[0] }
    end

    # @param pattern [Symbol]
    # @return [Boolean] Whether the line defines this pattern (NONE isn't a pattern).
    def has_pattern?(pattern)
      return @patterns.any? { |p| p[0] == pattern }
    end

    # @param pattern [Symbol]
    # @return [Array, nil] The pattern's [id, real name, weight, dominance] entry.
    def pattern_entry(pattern)
      return @patterns.find { |p| p[0] == pattern }
    end

    # @brief A pattern's untranslated name.
    # @param pattern [Symbol]
    # @return [String, nil]
    def real_pattern_name(pattern)
      return pattern_entry(pattern)&.[](1)
    end

    # @brief A pattern's name in the player's language.
    # @param pattern [Symbol]
    # @return [String, nil]
    def pattern_name(pattern)
      real = real_pattern_name(pattern)
      return nil if !real
      return pbGetMessageFromHash(MessageTypes::POKEMON_PATTERN_NAMES, real)
    end

    # @return [Integer] The roll weight of "no pattern", with the default filled in.
    def none_weight
      return @no_pattern_weight || GraphicsSettings::DEFAULT_NO_PATTERN_WEIGHT
    end

    # @brief Every possible outcome of a roll and its weight, "no pattern" first.
    # @return [Array<Array(Symbol, Integer)>]
    def weighted_outcomes
      ret = [[NONE, none_weight]]
      @patterns.each { |p| ret.push([p[0], p[2]]) }
      return ret
    end

    # @brief How strongly a parent with this pattern passes it on.
    # @param pattern [Symbol] A pattern id, or NONE.
    # @return [Integer]
    def dominance(pattern)
      if pattern == NONE
        return @no_pattern_dominance || GraphicsSettings::DEFAULT_PATTERN_DOMINANCE
      end
      return pattern_entry(pattern)&.[](3) || GraphicsSettings::DEFAULT_PATTERN_DOMINANCE
    end
  end
end

#==================================================================
# module Compiler
#==================================================================
# @brief Compiles and writes pokemon_patterns.txt. Patterns are compiled just before
# trainers, so species exist already and trainers' Pattern values can be checked.
module Compiler
  class << self
    alias __pattern_compile_trainers compile_trainers unless method_defined?(:__pattern_compile_trainers)
    alias __pattern_write_all write_all unless method_defined?(:__pattern_write_all)

    # @brief Compiles pokemon_patterns.txt, then trainers.
    # @param paths [Array<String>] The trainer PBS files.
    def compile_trainers(*paths)
      pattern_paths = get_all_pbs_files_to_compile[:PokemonPattern]&.[](1) || []
      compile_pokemon_patterns(*pattern_paths)
      __pattern_compile_trainers(*paths)
    end

    # @brief Compiles pokemon_patterns.txt (or removes the compiled data if there's no file).
    # @param paths [Array<String>]
    def compile_pokemon_patterns(*paths)
      if paths.none? { |p| FileTest.exist?(p) }
        GameData::PokemonPattern::DATA.clear
        dat = "Data/#{GameData::PokemonPattern::DATA_FILENAME}"
        File.delete(dat) if FileTest.exist?(dat)
        return
      end
      compile_PBS_file_generic(GameData::PokemonPattern, *paths) do |final_validate, hash|
        (final_validate) ? validate_all_compiled_pokemon_patterns : validate_compiled_pokemon_pattern(hash)
      end
    end

    # @brief Checks one compiled evolution line.
    # @param hash [Hash]
    def validate_compiled_pokemon_pattern(hash)
      species = hash[:id]
      root = GameData::Species.get(species).get_baby_species(false)
      if root != species
        raise _INTL("Patterns must be defined on the first species of an evolution line ([{1}], not [{2}]).",
                    root, species) + "\n" + FileLineData.linereport
      end
      seen = []
      (hash[:patterns] || []).each do |pattern|
        id = pattern[0]
        if id == GameData::PokemonPattern::NONE
          raise _INTL("NONE can't be used as a pattern id (it means \"no pattern\").") + "\n" + FileLineData.linereport
        end
        if seen.include?(id)
          raise _INTL("Pattern {1} is defined twice for {2}.", id, species) + "\n" + FileLineData.linereport
        end
        seen.push(id)
      end
      if seen.empty?
        raise _INTL("{1} has no Pattern lines.", species) + "\n" + FileLineData.linereport
      end
    end

    # @brief Checks lines against each other, and stores pattern names for translating.
    def validate_all_compiled_pokemon_patterns
      names = []
      GameData::PokemonPattern.each do |line|
        line.patterns.each { |pattern| names.push(pattern[1]) }
      end
      MessageTypes.setMessagesAsHash(MessageTypes::POKEMON_PATTERN_NAMES, names.uniq)
      PatternSprites.clear_cache if defined?(PatternSprites)
    end

    # @brief Writes pokemon_patterns.txt from the loaded data.
    def write_pokemon_patterns
      write_PBS_file_generic(GameData::PokemonPattern)
    end

    # @brief Writes every PBS file, including pokemon_patterns.txt.
    def write_all
      __pattern_write_all
      write_pokemon_patterns
    end
  end
end
