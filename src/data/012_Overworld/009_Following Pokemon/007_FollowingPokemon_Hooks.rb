#===============================================================================
# Following Pokémon: walking together, and hooks into the rest of the game.
#===============================================================================
module FollowingPokemon
  # Character ID of the following Pokémon in event commands (like -1 is the
  # player). In Tiled event scripts it's `pokemon_follower`.
  CHARACTER_ID = -2

  module_function

  # Called each time the player takes a step. While the Pokémon is out, it
  # slowly grows friendlier, sometimes finds an item, and now and then shows
  # an emote.
  def on_step
    return if !active?
    pkmn = event.pokemon
    return if !pkmn
    d = data
    # Friendship
    d.friendship_steps += 1
    if d.friendship_steps >= FRIENDSHIP_STEPS
      d.friendship_steps = 0
      pkmn.changeHappiness("walking")
    end
    # Finding items
    d.item_steps += 1
    if d.item_steps >= ITEM_STEPS
      d.item_steps = 0
      if !d.found_item && rand(100) < ITEM_CHANCE
        d.found_item = random_item
        emote(ITEM_FOUND_EMOTE) if d.found_item
        return
      end
    end
    # Ambient emotes
    d.emote_steps += 1
    if d.emote_steps >= AMBIENT_EMOTE_STEPS
      d.emote_steps = 0
      emote(ambient_emote(pkmn)) if rand(100) < AMBIENT_EMOTE_CHANCE
    end
  end

  # A random item from ITEMS, by weight. Items that don't exist in this game
  # are left out.
  # @return [Symbol, nil]
  def random_item
    items = ITEMS.select { |item, _weight| GameData::Item.exists?(item) }
    total = items.sum { |_item, weight| weight }
    return nil if total <= 0
    roll = rand(total)
    items.each do |item, weight|
      return item if roll < weight
      roll -= weight
    end
    return nil
  end

  # The emote the Pokémon shows by itself, depending on how it feels.
  # @param pkmn [Pokemon]
  # @return [Symbol]
  def ambient_emote(pkmn)
    return ITEM_FOUND_EMOTE if data.found_item
    return :poison if pkmn.status == :POISON
    return :ellipsis if pkmn.status != :NONE || pkmn.hp <= pkmn.totalhp / 4
    return :heart if pkmn.happiness >= 220
    return [:happy, :music].sample if pkmn.happiness >= 150
    return [:smile, :question].sample if pkmn.happiness >= 50
    return :angry
  end
end

EventHandlers.add(:on_player_step_taken, :following_pokemon,
  proc {
    FollowingPokemon.on_step
  }
)

#===============================================================================
# Event commands can use the following Pokémon as a character (CHARACTER_ID),
# e.g. for Set Move Route and Show Animation.
#===============================================================================
class Interpreter
  alias __followingpokemon__get_character get_character unless method_defined?(:__followingpokemon__get_character)

  def get_character(parameter = 0)
    return FollowingPokemon.event if parameter == FollowingPokemon::CHARACTER_ID
    return __followingpokemon__get_character(parameter)
  end

  # Recover All: at a Pokémon Center, the following Pokémon goes back into its
  # Poké Ball to be healed with the others, and comes back out once the nurse's
  # event has finished.
  alias __followingpokemon__command_314 command_314 unless method_defined?(:__followingpokemon__command_314)

  def command_314
    if FollowingPokemon::POKEMON_CENTER_ANIMATION && FollowingPokemon.active? &&
       $PokemonGlobal.pokecenterMapId == $game_map.map_id
      FollowingPokemon.recall_and_wait(:pokemon_center)
    end
    return __followingpokemon__command_314
  end
end

#===============================================================================
# Surf and Fly: the following Pokémon goes back into its Poké Ball before the
# player starts surfing or flies away. It stays in while surfing or diving (see
# FollowingPokemon.hide_reasons), and comes back out after landing.
#===============================================================================
alias __followingpokemon__pbStartSurfing pbStartSurfing unless defined?(__followingpokemon__pbStartSurfing)

def pbStartSurfing
  FollowingPokemon.recall_and_wait
  __followingpokemon__pbStartSurfing
end

alias __followingpokemon__pbFlyToNewLocation pbFlyToNewLocation unless defined?(__followingpokemon__pbFlyToNewLocation)

def pbFlyToNewLocation(*args, &block)
  return __followingpokemon__pbFlyToNewLocation(*args, &block) if $game_temp.fly_destination.nil?
  FollowingPokemon.recall_and_wait(:flying)
  begin
    return __followingpokemon__pbFlyToNewLocation(*args, &block)
  ensure
    FollowingPokemon.release(:flying)
  end
end
