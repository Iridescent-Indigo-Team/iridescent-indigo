#================================================================================================
# Pokémon Iridescent Indigo Graphics/Pokemon Patterns - 002_Generation.rb
#================================================================================================
# Each Pokémon of a line with patterns has one pattern, stored as a symbol in @pattern:
#
#   nil     - not rolled yet (rolled the first time it's needed, like a form)
#   :NONE   - rolled, no pattern (drawn with the normal sprites)
#   :SPOTTED etc. - one of its line's patterns
#
# Patterns are separate from forms: they never change @form, and a pattern is drawn on top
# of whatever form, gender and shininess the Pokémon has. A Pokémon keeps its pattern when
# it evolves, since every species of a line shares the same patterns.

#==================================================================
# module PatternData
#==================================================================
# @brief Looks up patterns and rolls them.
module PatternData
  # @brief The pattern id that means "no pattern".
  NONE = GameData::PokemonPattern::NONE

  module_function

  # @brief Whether patterns are drawn at all (GraphicsSettings::PATTERNS_ENABLED).
  # @return [Boolean]
  def enabled?
    return GraphicsSettings::PATTERNS_ENABLED
  end

  # @brief The first species of a species' evolution line (ignoring incense).
  # @param species [Symbol, GameData::Species, nil] A species, or a "SPECIES_form" id.
  # @return [Symbol, nil] nil if the species doesn't exist.
  def line_root(species)
    data = GameData::Species.try_get(species)
    return nil if !data
    return GameData::Species.get(data.species).get_baby_species(false)
  end

  # @brief The patterns of a species' evolution line.
  # @param species [Symbol, GameData::Species, nil]
  # @return [GameData::PokemonPattern, nil] nil if the line has no patterns.
  def line_for(species)
    root = line_root(species)
    return nil if !root
    return GameData::PokemonPattern.try_get(root)
  end

  # @brief Whether a species' evolution line has any patterns.
  # @param species [Symbol, GameData::Species, nil]
  # @return [Boolean]
  def has_patterns?(species)
    return !line_for(species).nil?
  end

  # @brief The pattern ids of a species' evolution line.
  # @param species [Symbol]
  # @return [Array<Symbol>] Empty if the line has none.
  def ids_for(species)
    return line_for(species)&.pattern_ids || []
  end

  # @brief Whether a pattern belongs to a species' line. NONE is valid for any line that
  # has patterns.
  # @param species [Symbol]
  # @param pattern [Symbol, nil]
  # @return [Boolean]
  def valid?(species, pattern)
    return false if pattern.nil?
    line = line_for(species)
    return false if !line
    return pattern == NONE || line.has_pattern?(pattern)
  end

  # @brief A pattern's display name.
  # @param species [Symbol]
  # @param pattern [Symbol, nil]
  # @return [String] "No pattern" for NONE/nil; the id itself if the line doesn't define it.
  def name_for(species, pattern)
    return _INTL("No pattern") if pattern.nil? || pattern == NONE
    return line_for(species)&.pattern_name(pattern) || pattern.to_s
  end

  # @brief How strongly a parent with a pattern passes it on.
  # @param species [Symbol] Any species of the line.
  # @param pattern [Symbol] A pattern id, or NONE.
  # @return [Integer]
  def dominance_for(species, pattern)
    line = line_for(species)
    return 0 if !line
    return line.dominance(pattern)
  end

  # @brief Picks a pattern from a line's weights.
  # @param species [Symbol, Pokemon] Any species of the line, or a Pokémon of it.
  # @param rng [Random, #rand] The random number source (a seeded one for trainers).
  # @return [Symbol, nil] A pattern id, NONE, or nil if the line has no patterns.
  def roll(species, rng = Random)
    species = species.species if species.is_a?(Pokemon)
    line = line_for(species)
    return nil if !line
    outcomes = line.weighted_outcomes.select { |_id, weight| weight > 0 }
    total = outcomes.sum { |_id, weight| weight }
    return NONE if total <= 0
    pick = rng.rand(total)
    outcomes.each do |id, weight|
      return id if pick < weight
      pick -= weight
    end
    return NONE
  end

  # @brief The pattern a Pokémon is drawn with.
  # @param pkmn [Pokemon, nil]
  # @param species [Symbol, nil] Draw as this species instead (e.g. during evolution).
  # @return [Symbol, nil] nil when it's drawn with its normal sprites (no pattern, an egg,
  # patterns turned off, or a pattern its line doesn't have).
  def shown_pattern(pkmn, species = nil)
    return nil if !enabled? || !pkmn.is_a?(Pokemon) || pkmn.egg?
    species ||= pkmn.species
    pattern = pkmn.pattern
    return nil if pattern.nil? || pattern == NONE
    return nil if !valid?(species, pattern)
    return pattern
  end
end

#==================================================================
# class Pokemon
#==================================================================
# @brief A Pokémon's pattern.
class Pokemon
  # @brief This Pokémon's pattern. If it has none yet and its line has patterns, one is
  # rolled now and kept, the same way a form is worked out the first time it's needed.
  # Pokémon of lines without patterns stay unrolled, so a line given patterns later (even
  # in an update) still gives its existing Pokémon one.
  # @return [Symbol, nil] A pattern id, :NONE, or nil if its line has no patterns.
  def pattern
    if @pattern.nil?
      return nil if !PatternData.has_patterns?(@species)
      @pattern = PatternData.roll(@species)
    end
    return @pattern
  end

  # @brief Sets this Pokémon's pattern. It isn't checked against the Pokémon's line: a
  # pattern its line doesn't have is kept, but the normal sprites are drawn.
  # @param value [Symbol, String, nil] A pattern id, :NONE, or nil to roll again when next
  # needed.
  def pattern=(value)
    @pattern = (value.nil?) ? nil : value.to_s.upcase.to_sym
  end

  # @return [Boolean] Whether a pattern has been rolled or set.
  def pattern_rolled?
    return !@pattern.nil?
  end

  # @return [Symbol, nil] The stored pattern, without rolling one.
  def pattern_simple
    return @pattern
  end

  # @return [Boolean] Whether this Pokémon has one of its line's patterns (not :NONE).
  def patterned?
    pat = pattern
    return !pat.nil? && pat != PatternData::NONE && PatternData.valid?(@species, pat)
  end

  # @return [String] The display name of this Pokémon's pattern ("No pattern" if none).
  def pattern_name
    return PatternData.name_for(@species, pattern)
  end
end
