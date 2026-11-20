#===============================================================================
# Following Pokémon: talking to it.
#===============================================================================
# Talking to the following Pokémon first hands over any item it has found.
# Otherwise the dialogue handlers are tried in order of priority (lowest
# first); the first one that returns true has said something. Most handlers
# only speak some of the time, so the Pokémon says different things each time.
#
# Add your own handlers with FollowingPokemon::Dialogue.add, e.g.:
#   FollowingPokemon::Dialogue.add(:my_town, 33) do |pkmn|
#     next false if $game_map.map_id != 5
#     FollowingPokemon.emote(:music, true)
#     pbMessage(_INTL("{1} loves this town!", pkmn.name))
#     next true
#   end
# All text goes through _INTL with a literal string, so `make update-locales`
# adds it to every language's scripts.csv for translation.
#===============================================================================
module FollowingPokemon
  #=============================================================================
  # The dialogue handler registry.
  #=============================================================================
  module Dialogue
    @handlers = []

    module_function

    # Adds (or replaces) a dialogue handler.
    # @param id [Symbol] the handler's name
    # @param priority [Numeric] lower runs first
    # @yieldparam pkmn [Pokemon] the following Pokémon
    # @yieldreturn [Boolean] true if the handler said something
    def add(id, priority, &block)
      remove(id)
      @handlers.push([priority, id, block])
      @handlers.sort_by! { |handler| [handler[0], handler[1].to_s] }
    end

    # @param id [Symbol]
    def remove(id)
      @handlers.reject! { |handler| handler[1] == id }
    end

    # @return [Array<Symbol>] the handlers' names, in the order they run
    def ids
      return @handlers.map { |handler| handler[1] }
    end

    # Runs the handlers until one says something.
    # @param pkmn [Pokemon]
    # @return [Boolean] whether anything was said
    def run(pkmn)
      @handlers.each do |handler|
        return true if handler[2].call(pkmn)
      end
      return false
    end

    # Shows an emote over the following Pokémon, then a message.
    # @param emote [Symbol, nil] see FollowingPokemon.emote
    # @param message [String] the (already translated) message
    # @return [true]
    def say(emote, message)
      FollowingPokemon.emote(emote, true) if emote
      pbMessage(message)
      return true
    end

    # @param percent [Integer]
    # @return [Boolean] true percent% of the time
    def chance(percent)
      return rand(100) < percent
    end
  end

  module_function

  # Talks to the following Pokémon.
  # @return [Boolean] whether it could be talked to
  def talk
    return false if !active?
    ev = event
    pkmn = ev.pokemon
    return false if !pkmn
    $game_map.refresh if $game_map.need_refresh
    pbTurnTowardEvent(ev, $game_player)
    pkmn.play_cry
    if data.found_item
      give_found_item(pkmn)
    else
      Dialogue.run(pkmn)
    end
    return true
  end

  # The following Pokémon gives the player the item it found.
  # @param pkmn [Pokemon]
  def give_found_item(pkmn)
    item = data.found_item
    emote(:exclaim, true)
    pbMessage(_INTL("{1} seems to be holding something...", pkmn.name))
    if !GameData::Item.exists?(item)
      data.found_item = nil
      return
    end
    if !$bag.can_add?(item)
      pbMessage(_INTL("{1} found an item, but the Bag is full.", pkmn.name))
      return
    end
    pbMessage(_INTL("{1} found something and wants {2} to have it!", pkmn.name, $player.name))
    data.found_item = nil if pbReceiveItem(item)
  end
end

#===============================================================================
# Status problems and low HP.
#===============================================================================
FollowingPokemon::Dialogue.add(:status, 10) do |pkmn|
  d = FollowingPokemon::Dialogue
  case pkmn.status
  when :POISON
    next d.say(:poison, _INTL("{1} is shivering with the effects of being poisoned.", pkmn.name))
  when :BURN
    next d.say(:sad, _INTL("{1}'s burn looks painful.", pkmn.name))
  when :FROZEN
    next d.say(:ellipsis, _INTL("{1} seems very cold. It's frozen solid!", pkmn.name))
  when :SLEEP
    next d.say(:ellipsis, _INTL("{1} seems really tired.", pkmn.name))
  when :PARALYSIS
    next d.say(:ellipsis, _INTL("{1} is standing still and twitching.", pkmn.name))
  end
  next false
end

FollowingPokemon::Dialogue.add(:low_hp, 20) do |pkmn|
  d = FollowingPokemon::Dialogue
  next false if pkmn.hp > pkmn.totalhp / 4
  messages = [
    _INTL("{1} looks exhausted. It could use some rest.", pkmn.name),
    _INTL("{1} is tired out, but trying hard to keep up.", pkmn.name)
  ]
  next d.say(:sad, messages.sample)
end

#===============================================================================
# The current map: Pokémon Centers, map flags, and the town or route itself.
#===============================================================================
FollowingPokemon::Dialogue.add(:pokemon_center, 30) do |pkmn|
  d = FollowingPokemon::Dialogue
  next false if $PokemonGlobal.pokecenterMapId != $game_map.map_id || !d.chance(50)
  messages = [
    _INTL("{1} seems relieved to be in a Pokémon Center.", pkmn.name),
    _INTL("{1} is looking at the nurse curiously.", pkmn.name)
  ]
  next d.say(:smile, messages.sample)
end

FollowingPokemon::Dialogue.add(:map_flags, 31) do |pkmn|
  d = FollowingPokemon::Dialogue
  metadata = $game_map.metadata
  next false if !metadata || !d.chance(50)
  if metadata.has_flag?("PokemonLab")
    messages = [
      _INTL("{1} is touching some kind of switch.", pkmn.name),
      _INTL("{1} seems to want to touch the machinery.", pkmn.name)
    ]
    next d.say(:question, messages.sample)
  elsif metadata.dark_map
    messages = [
      _INTL("{1} is staying close to {2} in the dark.", pkmn.name, $player.name),
      _INTL("{1} is peering into the darkness.", pkmn.name)
    ]
    next d.say(:ellipsis, messages.sample)
  elsif metadata.safari_map
    next d.say(:music, _INTL("{1} is excited by all the wild Pokémon here!", pkmn.name))
  end
  next false
end

FollowingPokemon::Dialogue.add(:location, 32) do |pkmn|
  d = FollowingPokemon::Dialogue
  next false if !d.chance(30)
  map_name = $game_map.name
  region = $game_map.metadata&.town_map_position
  region_name = (region && GameData::TownMap.exists?(region[0])) ? GameData::TownMap.get(region[0]).name : nil
  if !$game_map.metadata&.outdoor_map
    messages = [
      _INTL("{1} is sniffing around {2}.", pkmn.name, map_name),
      _INTL("{1} is looking around {2} curiously.", pkmn.name, map_name)
    ]
    next d.say(:question, messages.sample)
  end
  messages = [
    _INTL("{1} seems to like {2}.", pkmn.name, map_name),
    _INTL("{1} is taking in the scenery of {2}.", pkmn.name, map_name)
  ]
  if region_name
    messages.push(_INTL("{1} seems happy to be exploring {2} with {3}.", pkmn.name, region_name, $player.name))
  end
  next d.say(:smile, messages.sample)
end

#===============================================================================
# The weather.
#===============================================================================
FollowingPokemon::Dialogue.add(:weather, 40) do |pkmn|
  d = FollowingPokemon::Dialogue
  next false if !$game_map.metadata&.outdoor_map || !d.chance(50)
  case $game_screen.weather_type
  when :Rain, :HeavyRain, :Storm
    if pkmn.hasType?(:WATER)
      next d.say(:music, _INTL("{1} is splashing happily in the rain!", pkmn.name))
    elsif pkmn.hasType?(:FIRE)
      next d.say(:sad, _INTL("{1} really doesn't like the rain.", pkmn.name))
    end
    next d.say(:ellipsis, _INTL("{1} is shaking the rain off its body.", pkmn.name))
  when :Snow, :Blizzard
    if pkmn.hasType?(:ICE)
      next d.say(:music, _INTL("{1} is playing happily in the snow!", pkmn.name))
    end
    next d.say(:ellipsis, _INTL("{1} is shivering in the cold.", pkmn.name))
  when :Sun
    if pkmn.hasType?(:FIRE) || pkmn.hasType?(:GRASS)
      next d.say(:happy, _INTL("{1} is basking in the sunlight.", pkmn.name))
    end
    next d.say(:ellipsis, _INTL("{1} seems to be feeling the heat.", pkmn.name))
  when :Sandstorm
    if pkmn.hasType?(:ROCK) || pkmn.hasType?(:GROUND) || pkmn.hasType?(:STEEL)
      next d.say(:smile, _INTL("{1} doesn't mind the sandstorm at all.", pkmn.name))
    end
    next d.say(:mad, _INTL("{1} is squinting in the swirling sand.", pkmn.name))
  when :Fog
    next d.say(:question, _INTL("{1} is peering through the fog.", pkmn.name))
  end
  next false
end

#===============================================================================
# The time of day.
#===============================================================================
FollowingPokemon::Dialogue.add(:time_of_day, 45) do |pkmn|
  d = FollowingPokemon::Dialogue
  next false if !d.chance(30)
  if PBDayNight.isNight?
    if pkmn.hasType?(:GHOST) || pkmn.hasType?(:DARK)
      next d.say(:happy, _INTL("{1} seems more lively now that it's night.", pkmn.name))
    end
    next d.say(:ellipsis, _INTL("{1} is yawning. It must be getting late.", pkmn.name))
  elsif PBDayNight.isMorning?
    next d.say(:smile, _INTL("{1} is stretching in the morning air.", pkmn.name))
  elsif PBDayNight.isEvening?
    next d.say(:smile, _INTL("{1} is gazing at the evening sky.", pkmn.name))
  end
  next false
end

#===============================================================================
# Particular species.
#===============================================================================
FollowingPokemon::Dialogue.add(:species, 50) do |pkmn|
  d = FollowingPokemon::Dialogue
  next false if !d.chance(40)
  case pkmn.species
  when :PIKACHU, :RAICHU, :PICHU
    next d.say(:happy, _INTL("{1}'s cheeks are crackling with electricity!", pkmn.name))
  when :EEVEE
    next d.say(:heart, _INTL("{1} is rubbing against {2}'s legs.", pkmn.name, $player.name))
  when :MEOWTH, :PERSIAN
    next d.say(:question, _INTL("{1} is eyeing something shiny on the ground.", pkmn.name))
  when :PSYDUCK
    next d.say(:question, _INTL("{1} is holding its head. It looks confused.", pkmn.name))
  when :SNORLAX
    next d.say(:ellipsis, _INTL("{1} looks like it wants a snack... and a nap.", pkmn.name))
  when :JIGGLYPUFF, :WIGGLYTUFF, :IGGLYBUFF
    next d.say(:music, _INTL("{1} is humming a sleepy little song.", pkmn.name))
  when :MAGIKARP
    next d.say(:ellipsis, _INTL("{1} is flopping around energetically.", pkmn.name))
  when :DITTO
    next d.say(:question, _INTL("{1} is trying to look like {2}.", pkmn.name, $player.name))
  when :SLOWPOKE
    next d.say(:ellipsis, _INTL("{1} is staring into space...", pkmn.name))
  end
  next false
end

#===============================================================================
# The Pokémon's type.
#===============================================================================
FollowingPokemon::Dialogue.add(:type, 60) do |pkmn|
  d = FollowingPokemon::Dialogue
  next false if !d.chance(40)
  case pkmn.types.first
  when :NORMAL   then next d.say(:smile, _INTL("{1} is trotting along at {2}'s side.", pkmn.name, $player.name))
  when :FIRE     then next d.say(:happy, _INTL("{1} is giving off a pleasant warmth.", pkmn.name))
  when :WATER    then next d.say(:smile, _INTL("{1} looks like it would like a swim.", pkmn.name))
  when :GRASS    then next d.say(:smile, _INTL("{1} smells faintly of fresh leaves.", pkmn.name))
  when :ELECTRIC then next d.say(:happy, _INTL("{1}'s fur is standing on end with static!", pkmn.name))
  when :ICE      then next d.say(:smile, _INTL("{1} is giving off a cool breeze.", pkmn.name))
  when :FIGHTING then next d.say(:mad, _INTL("{1} is practicing its moves!", pkmn.name))
  when :POISON   then next d.say(:smile, _INTL("{1} is careful not to touch {2} with its poison.", pkmn.name, $player.name))
  when :GROUND   then next d.say(:smile, _INTL("{1} is digging at the ground.", pkmn.name))
  when :FLYING   then next d.say(:music, _INTL("{1} is looking up at the sky.", pkmn.name))
  when :PSYCHIC  then next d.say(:question, _INTL("{1} seems to know what {2} is thinking.", pkmn.name, $player.name))
  when :BUG      then next d.say(:smile, _INTL("{1} is busily inspecting a leaf.", pkmn.name))
  when :ROCK     then next d.say(:smile, _INTL("{1} is standing firm and steady.", pkmn.name))
  when :GHOST    then next d.say(:ellipsis, _INTL("{1} is grinning mischievously.", pkmn.name))
  when :DRAGON   then next d.say(:mad, _INTL("{1} let out a mighty roar!", pkmn.name))
  when :DARK     then next d.say(:ellipsis, _INTL("{1} is watching the shadows closely.", pkmn.name))
  when :STEEL    then next d.say(:smile, _INTL("{1}'s body is gleaming.", pkmn.name))
  when :FAIRY    then next d.say(:heart, _INTL("{1} is twinkling cheerfully.", pkmn.name))
  end
  next false
end

#===============================================================================
# How the Pokémon feels about the player (always says something).
#===============================================================================
FollowingPokemon::Dialogue.add(:friendship, 90) do |pkmn|
  d = FollowingPokemon::Dialogue
  if pkmn.happiness >= 220
    messages = [
      _INTL("{1} is gazing at {2} with total trust.", pkmn.name, $player.name),
      _INTL("{1} loves walking with {2}!", pkmn.name, $player.name),
      _INTL("{1} is snuggling up to {2}.", pkmn.name, $player.name)
    ]
    next d.say(:heart, messages.sample)
  elsif pkmn.happiness >= 150
    messages = [
      _INTL("{1} is happily following {2}.", pkmn.name, $player.name),
      _INTL("{1} is skipping along cheerfully.", pkmn.name),
      _INTL("{1} looks very happy!", pkmn.name)
    ]
    next d.say(:happy, messages.sample)
  elsif pkmn.happiness >= 100
    messages = [
      _INTL("{1} is keeping pace with {2}.", pkmn.name, $player.name),
      _INTL("{1} seems to be enjoying the walk.", pkmn.name),
      _INTL("{1} turned to look at {2}.", pkmn.name, $player.name)
    ]
    next d.say(:smile, messages.sample)
  elsif pkmn.happiness >= 50
    messages = [
      _INTL("{1} is looking around restlessly.", pkmn.name),
      _INTL("{1} is following {2}, a little warily.", pkmn.name, $player.name)
    ]
    next d.say(:ellipsis, messages.sample)
  end
  messages = [
    _INTL("{1} is ignoring {2}.", pkmn.name, $player.name),
    _INTL("{1} turned away from {2}.", pkmn.name, $player.name)
  ]
  next d.say(:angry, messages.sample)
end
