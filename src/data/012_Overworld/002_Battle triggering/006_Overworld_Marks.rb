#===============================================================================
# Marks. Wild Pokémon may be generated with a mark depending on the conditions
# of the encounter (time, weather, fishing, Sweet Scent, the player's birthday)
# or by pure chance, and party Pokémon can earn party marks by doing things
# with the player. The Mark Charm makes marks more likely. See docs/MARKS.md.
#===============================================================================
class Game_Temp
  # @return [Boolean] whether the current encounter was lured by Sweet Scent or
  #   Honey (used for the Curry Mark)
  attr_accessor :used_sweet_scent
end

class PokemonGlobalMetadata
  # @return [Integer] steps taken since the last Partner Mark check
  attr_writer :partner_mark_steps

  # @return [Integer] steps taken since the last Partner Mark check
  def partner_mark_steps
    @partner_mark_steps ||= 0
    return @partner_mark_steps
  end
end

#-------------------------------------------------------------------------------
# Picking marks
#-------------------------------------------------------------------------------
# @return [Boolean] whether the player has the Mark Charm
def pbHasMarkCharm?
  return $bag&.has?(:MARKCHARM) || false
end

# @param category [Symbol] a mark category, e.g. :personality (see
#   Pokemon#hasRibbonType? for the list)
# @return [Array<Symbol>] the IDs of all marks in that category
def pbMarksOfType(category)
  ret = []
  GameData::Ribbon.each do |data|
    next if !data.mark?
    ret.push(data.id) if pbRibbonDataMatches?(data, category)
  end
  return ret
end

# @param data [GameData::Ribbon]
# @param category [Symbol]
# @return [Boolean] whether the ribbon/mark belongs to the category
def pbRibbonDataMatches?(data, category)
  case category
  when :time        then return data.time_mark?
  when :weather     then return data.weather_mark?
  when :encounter   then return data.encounter_mark?
  when :rarity      then return data.rarity_mark?
  when :personality then return data.personality_mark?
  when :size        then return data.size_mark?
  when :party       then return data.party_mark?
  when :boss        then return data.boss_mark?
  end
  return false
end

# @return [Symbol, nil] a random personality mark
def pbGetPersonalityMark
  return pbMarksOfType(:personality).sample
end

# @param time [Time, nil] the time to check (now by default)
# @return [Symbol] the time mark for the time of day
def pbGetTimeMark(time = nil)
  return :SLEEPYTIMEMARK if PBDayNight.isNight?(time)
  return :DAWNMARK if PBDayNight.isMorning?(time)
  return :DUSKMARK if PBDayNight.isEvening?(time)
  return :LUNCHTIMEMARK
end

# @param weather [Symbol, nil] an overworld weather ID (the current one if nil)
# @return [Symbol, nil] the weather mark for that weather, or nil if none
def pbGetWeatherMark(weather = nil)
  weather ||= $game_screen&.weather_type || :None
  case weather
  when :Rain, :HeavyRain then return :RAINYMARK
  when :Storm            then return :STORMYMARK
  when :Snow             then return :SNOWYMARK
  when :Blizzard         then return :BLIZZARDMARK
  when :Sandstorm        then return :SANDSTORMMARK
  when :Sun              then return :DRYMARK
  when :Fog              then return :MISTYMARK
  when :Cloudy, :Overcast then return :CLOUDYMARK   # Not in Essentials by default
  end
  return nil
end

# @return [Boolean] whether the current encounter is a fishing encounter
def pbFishingEncounter?
  enc_type = $game_temp&.encounter_type
  return false if !enc_type
  enc_data = GameData::EncounterType.try_get(enc_type)
  return enc_data && enc_data.type == :fishing
end

# Rolls for a mark in the main series' order. Each roll stops at the first mark
# found; there are more rolls with the Mark Charm.
# @return [Symbol, nil] the ID of the mark rolled, or nil if none
def pbRollWildMarkID
  odds = Settings::WILD_MARK_ODDS
  rolls = Settings::WILD_MARK_ROLLS
  rolls += Settings::MARK_CHARM_EXTRA_ROLLS if pbHasMarkCharm?
  weather_mark = pbGetWeatherMark
  rolls.times do
    ret = nil
    if odds[:rare] && rand(odds[:rare]) == 0
      ret = :RAREMARK
    elsif odds[:personality] && rand(odds[:personality]) == 0
      ret = pbGetPersonalityMark
    elsif odds[:uncommon] && rand(odds[:uncommon]) == 0
      ret = :UNCOMMONMARK
    elsif weather_mark && odds[:weather] && rand(odds[:weather]) == 0
      ret = weather_mark
    elsif odds[:time] && rand(odds[:time]) == 0
      ret = pbGetTimeMark
    elsif pbFishingEncounter? && odds[:fishing] && rand(odds[:fishing]) == 0
      ret = :FISHINGMARK
    elsif $game_temp&.used_sweet_scent && odds[:curry] && rand(odds[:curry]) == 0
      ret = :CURRYMARK
    elsif pbPlayerBirthday? && odds[:destiny] && rand(odds[:destiny]) == 0
      ret = :DESTINYMARK   # Only on the player's birthday
    end
    return ret if ret && GameData::Ribbon.exists?(ret)
  end
  return nil
end

# Gives a wild Pokémon the marks it would get in the current situation: a
# rolled mark (see pbRollWildMarkID), plus the Mini/Jumbo Mark if it is as
# small/big as it can be. A rolled mark's title is affixed if
# Settings::AFFIX_WILD_MARK_TITLES is true.
# @param pkmn [Pokemon] the wild Pokémon
# @return [Symbol, nil] the ID of the rolled mark, if any
def pbRollWildMark(pkmn)
  return nil if pkmn.shadowPokemon?
  if Settings::GUARANTEED_WILD_SIZE_MARKS
    pkmn.giveRibbon(:MINIMARK) if pkmn.min_size? && GameData::Ribbon.exists?(:MINIMARK)
    pkmn.giveRibbon(:JUMBOMARK) if pkmn.max_size? && GameData::Ribbon.exists?(:JUMBOMARK)
  end
  mark = pbRollWildMarkID
  if mark
    pkmn.giveRibbon(mark)
    pkmn.affixed_ribbon = mark if Settings::AFFIX_WILD_MARK_TITLES && !pkmn.affixed_ribbon
  end
  if Settings::AFFIX_WILD_MARK_TITLES && !pkmn.affixed_ribbon
    size_mark = pkmn.marks.find { |m| GameData::Ribbon.get(m).size_mark? }
    pkmn.affixed_ribbon = size_mark if size_mark
  end
  return mark
end

EventHandlers.add(:on_wild_pokemon_created, :roll_wild_marks,
  proc { |pkmn|
    next if $game_switches && $game_switches[Settings::NO_WILD_MARKS_SWITCH]
    pbRollWildMark(pkmn)
  }
)

#-------------------------------------------------------------------------------
# Giving marks
#-------------------------------------------------------------------------------
# Gives a mark to a Pokémon.
# @param pkmn [Pokemon]
# @param mark [Symbol] the mark's ID
# @param affix [Boolean] whether to also affix the mark's title
# @return [Boolean] whether the Pokémon got the mark (false if it already had
#   it or the mark doesn't exist)
def pbGiveMark(pkmn, mark, affix = false)
  return false if !pkmn || pkmn.egg? || !GameData::Ribbon.exists?(mark) || pkmn.hasRibbon?(mark)
  pkmn.giveRibbon(mark)
  pkmn.affixed_ribbon = mark if affix
  return pkmn.hasRibbon?(mark)
end

# Gives a mark to each able party Pokémon that passes a random check.
# @param mark [Symbol] the mark's ID
# @param odds [Integer] 1 in odds chance per Pokémon (halved by the Mark Charm)
# @param condition [Proc, nil] an extra check for each Pokémon
# @return [Array<Pokemon>] the Pokémon that got the mark
def pbGiveMarkToParty(mark, odds = Settings::PARTY_MARK_ODDS, condition = nil)
  ret = []
  return ret if !$player || !GameData::Ribbon.exists?(mark)
  odds = [odds / 2, 1].max if pbHasMarkCharm?
  $player.able_party.each do |pkmn|
    next if pkmn.hasRibbon?(mark) || pkmn.shadowPokemon?
    next if condition && !condition.call(pkmn)
    next if rand(odds) > 0
    pkmn.giveRibbon(mark)
    ret.push(pkmn)
  end
  return ret
end

#-------------------------------------------------------------------------------
# Party marks
#-------------------------------------------------------------------------------
# Partner Mark: every so many steps, each able party Pokémon with high enough
# happiness may get it.
EventHandlers.add(:on_player_step_taken, :partner_mark,
  proc {
    $PokemonGlobal.partner_mark_steps += 1
    next if $PokemonGlobal.partner_mark_steps < Settings::PARTNER_MARK_STEPS
    $PokemonGlobal.partner_mark_steps = 0
    pbGiveMarkToParty(:PARTNERMARK, Settings::PARTY_MARK_ODDS,
                      proc { |pkmn| pkmn.happiness >= Settings::PARTNER_MARK_HAPPINESS })
  }
)

# Itemfinder Mark: may be given to the lead Pokémon when an item is found in
# the overworld (called by pbItemBall).
def pbCheckItemfinderMark
  pkmn = $player&.first_able_pokemon
  return if !pkmn || pkmn.hasRibbon?(:ITEMFINDERMARK)
  odds = Settings::PARTY_MARK_ODDS
  odds = [odds / 2, 1].max if pbHasMarkCharm?
  pbGiveMark(pkmn, :ITEMFINDERMARK) if rand(odds) == 0
end

# Gourmand Mark: may be given to party Pokémon when berries are picked or
# bought (called by pbPickBerry and the Poké Mart).
def pbCheckGourmandMark
  pbGiveMarkToParty(:GOURMANDMARK)
end
