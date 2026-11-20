#===============================================================================
# Pokémon size. Every Pokémon has a size scale from 0 (smallest) to 255
# (largest), rolled when it is created (see Pokemon#scale). It doesn't change
# how the Pokémon looks, but decides the Mini/Jumbo Marks and its exact height,
# and can be compared (e.g. for a "biggest Magikarp" event).
#===============================================================================
class Pokemon
  # Size categories, smallest first, with the highest scale in each.
  SIZE_CATEGORIES = [
    [:XXXS, 0],
    [:XXS,  30],
    [:XS,   60],
    [:S,    99],
    [:M,    160],
    [:L,    195],
    [:XL,   241],
    [:XXL,  254],
    [:XXXL, 255]
  ]

  # @return [Symbol] this Pokémon's size category, from :XXXS to :XXXL
  def size_category
    SIZE_CATEGORIES.each { |cat| return cat[0] if scale <= cat[1] }
    return SIZE_CATEGORIES.last[0]
  end

  # @param category [Symbol, nil] a size category (this Pokémon's if nil)
  # @return [String] the translated name of the size category
  def size_name(category = nil)
    case category || size_category
    when :XXXS then return _INTL("XXXS")
    when :XXS  then return _INTL("XXS")
    when :XS   then return _INTL("XS")
    when :S    then return _INTL("Small")
    when :M    then return _INTL("Medium")
    when :L    then return _INTL("Large")
    when :XL   then return _INTL("XL")
    when :XXL  then return _INTL("XXL")
    end
    return _INTL("XXXL")
  end

  # @return [Boolean] whether this Pokémon is as small as possible
  def min_size?
    return scale == 0
  end

  # @return [Boolean] whether this Pokémon is as large as possible
  def max_size?
    return scale == 255
  end

  # This Pokémon's own height, from its species' height and its scale (from
  # 80% of the species' height at scale 0 to 120% at scale 255).
  # @return [Float] the height in decimetres (0.1 metres), like species heights
  def scaled_height
    return height * (0.8 + (0.4 * scale / 255.0))
  end

  # @return [String] this Pokémon's height as text, in feet and inches in the US
  #   and in metres elsewhere
  def scaled_height_text
    if System.user_language[3..4] == "US"
      inches = (scaled_height / 0.254).round
      return _ISPRINTF("{1:d}'{2:02d}\"", inches / 12, inches % 12)
    end
    return _ISPRINTF("{1:.2f} m", scaled_height / 10.0)
  end

  # Compares this Pokémon's size with another's. Pokémon of the same species
  # are compared by scale, others by their scaled height.
  # @param other [Pokemon]
  # @return [Integer] -1 if this Pokémon is smaller, 0 if the same, 1 if bigger
  def compare_size(other)
    return scale <=> other.scale if species == other.species
    return scaled_height <=> other.scaled_height
  end

  # @param other [Pokemon]
  # @return [Boolean] whether this Pokémon is bigger than other
  def bigger_than?(other)
    return compare_size(other) > 0
  end

  # @param other [Pokemon]
  # @return [Boolean] whether this Pokémon is smaller than other
  def smaller_than?(other)
    return compare_size(other) < 0
  end
end

#===============================================================================
# Size records, for events that compare the size of the player's Pokémon with
# the biggest one shown so far.
#===============================================================================
class PokemonGlobalMetadata
  # @return [Hash] the biggest Pokémon shown for each size record, as
  #   {record_id => [species, scale, scaled height, name]}
  def size_records
    @size_records ||= {}
    return @size_records
  end
end

# Lets the player choose a party Pokémon and compares its size with a record.
# The record is updated if the chosen Pokémon is bigger (or there was none).
# @example A "biggest Magikarp" event
#   result = pbCheckPokemonSize(:MAGIKARP_RECORD, :MAGIKARP)
#   (result == :bigger) ? pbMessage("Wow!") : pbMessage("Not big enough...")
# @param record_id [Symbol, String] the name of the record to compare with
# @param species [Symbol, nil] only Pokémon of this species can be chosen
# @param show_messages [Boolean] whether to show the standard result messages
# @return [Symbol, nil] :new (no previous record), :bigger, :same, :smaller,
#   or nil if no Pokémon was chosen
def pbCheckPokemonSize(record_id, species = nil, show_messages = true)
  species = GameData::Species.get(species).species if species
  chosen = -1
  pbFadeOutIn do
    scene = PokemonParty_Scene.new
    screen = PokemonPartyScreen.new(scene, $player.party)
    chosen = screen.pbChooseAblePokemon(proc { |pkmn|
      next !pkmn.egg? && (!species || pkmn.species == species)
    }, false)
  end
  return nil if chosen < 0
  pkmn = $player.party[chosen]
  record = $PokemonGlobal.size_records[record_id]
  if record
    result = (pkmn.species == record[0]) ? pkmn.scale <=> record[1] : pkmn.scaled_height <=> record[2]
    result = { 1 => :bigger, 0 => :same, -1 => :smaller }[result]
  else
    result = :new
  end
  if [:new, :bigger].include?(result)
    $PokemonGlobal.size_records[record_id] = [pkmn.species, pkmn.scale, pkmn.scaled_height, pkmn.name]
  end
  if show_messages
    case result
    when :new
      pbMessage(_INTL("{1} is {2} tall! That's the new record!", pkmn.name, pkmn.scaled_height_text))
    when :bigger
      pbMessage(_INTL("{1} is {2} tall! That's bigger than the record of {3}!",
                      pkmn.name, pkmn.scaled_height_text, record[3]))
    when :same
      pbMessage(_INTL("{1} is exactly the same size as the record of {2}!", pkmn.name, record[3]))
    when :smaller
      pbMessage(_INTL("{1} is {2} tall. That's smaller than the record of {3}...",
                      pkmn.name, pkmn.scaled_height_text, record[3]))
    end
  end
  return result
end

# @param record_id [Symbol, String]
# @return [Array, nil] the size record (see PokemonGlobalMetadata#size_records)
def pbGetSizeRecord(record_id)
  return $PokemonGlobal.size_records[record_id]
end

# Clears a size record.
# @param record_id [Symbol, String]
def pbClearSizeRecord(record_id)
  $PokemonGlobal.size_records.delete(record_id)
end
