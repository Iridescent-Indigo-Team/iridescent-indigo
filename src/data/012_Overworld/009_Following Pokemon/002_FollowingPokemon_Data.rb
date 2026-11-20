#===============================================================================
# Following Pokémon: saved data.
#===============================================================================
# The following Pokémon's state, saved in $PokemonGlobal.pokemon_follower. It
# is a FollowerData so that Game_Follower (and so the following Pokémon's
# event) can be built from it, but it isn't in $PokemonGlobal.followers.
#===============================================================================
class PokemonFollowerData < FollowerData
  # The name the following Pokémon's event and data have.
  EVENT_NAME = "FollowingPokemon reflection"

  # @return [Boolean] whether an event has turned the following Pokémon off
  #   (FollowingPokemon.toggle)
  attr_accessor :toggled_off
  # @return [Array<Symbol>] reasons scripts have given for keeping the Pokémon
  #   in its Poké Ball (FollowingPokemon.hide/show)
  attr_reader   :hide_reasons
  # @return [Array, nil] what the shown Pokémon looked like when its sprite was
  #   last set (FollowingPokemon.signature), to notice party changes
  attr_accessor :signature
  # @return [Integer, nil] personal ID of the Pokémon that's out
  attr_accessor :personal_id
  # @return [Integer] steps walked towards the next friendship gain
  attr_accessor :friendship_steps
  # @return [Integer] steps walked towards the next item search
  attr_accessor :item_steps
  # @return [Integer] steps walked towards the next ambient emote
  attr_accessor :emote_steps
  # @return [Symbol, nil] an item the Pokémon has found and will give to the
  #   player when talked to
  attr_accessor :found_item

  def initialize(map_id, x, y, direction)
    super(map_id, 0, EVENT_NAME, map_id, x, y, direction, "", 0)
    @name             = :pokemon
    @out              = false
    @toggled_off      = false
    @hide_reasons     = []
    @signature        = nil
    @personal_id      = nil
    @friendship_steps = 0
    @item_steps       = 0
    @emote_steps      = 0
    @found_item       = nil
  end

  # @return [Boolean] whether the Pokémon is out of its Poké Ball, walking
  #   behind the player
  def out?
    return @out
  end

  # @param value [Boolean]
  def out=(value)
    @out = value
    @invisible_after_transfer = false if !value
  end

  def visible?
    return @out && super
  end

  # Talking to the following Pokémon.
  # @param event [Game_FollowingPokemon]
  def interact(event)
    FollowingPokemon.talk
  end
end

#===============================================================================
#
#===============================================================================
class PokemonGlobalMetadata
  attr_writer :pokemon_follower

  # The following Pokémon's saved data, created the first time it's needed
  # (including for saves made before following Pokémon existed).
  # @return [PokemonFollowerData]
  def pokemon_follower
    if !@pokemon_follower
      map_id = $game_map&.map_id || 0
      @pokemon_follower = PokemonFollowerData.new(map_id, $game_player&.x || 0,
                                                  $game_player&.y || 0,
                                                  $game_player&.direction || 2)
    end
    return @pokemon_follower
  end
end
