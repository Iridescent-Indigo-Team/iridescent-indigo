#===============================================================================
# Data saved in $PokemonGlobal.followers.
#===============================================================================
class FollowerData
  attr_accessor :original_map_id
  attr_accessor :event_id
  attr_accessor :event_name
  attr_accessor :current_map_id
  attr_accessor :x, :y
  attr_accessor :direction
  attr_accessor :character_name, :character_hue
  attr_accessor :name
  attr_accessor :common_event_id
  attr_accessor :visible
  attr_accessor :invisible_after_transfer

  def initialize(original_map_id, event_id, event_name, current_map_id, x, y,
                 direction, character_name, character_hue)
    @original_map_id          = original_map_id
    @event_id                 = event_id
    @event_name               = event_name
    @current_map_id           = current_map_id
    @x                        = x
    @y                        = y
    @direction                = direction
    @character_name           = character_name
    @character_hue            = character_hue
    @name                     = nil
    @common_event_id          = nil
    @visible                  = true
    @invisible_after_transfer = false
  end

  def visible?
    return @visible && !@invisible_after_transfer
  end

  def interact(event)
    return if !event || event.list.size <= 1
    return if !@common_event_id
    # Start event
    $game_map.refresh if $game_map.need_refresh
    event.lock
    pbMapInterpreter.setup(event.list, event.id, event.map.map_id)
  end
end

#===============================================================================
# Permanently stores data of follower events (i.e. in save files).
#===============================================================================
class PokemonGlobalMetadata
  attr_accessor :dependentEvents   # Deprecated - to be removed in v22
  attr_writer   :followers

  def followers
    @followers = [] if !@followers
    return @followers
  end
end

#===============================================================================
# Stores Game_Follower instances just for the current play session.
#===============================================================================
class Game_Temp
  attr_writer :followers

  def followers
    @followers = Game_FollowerFactory.new if !@followers
    return @followers
  end
end

#===============================================================================
# Holds the follower objects (Game_Follower) for the current play session and
# moves them along behind the player. Followers form a chain: the player leads
# the first follower, which leads the second, and so on. The following Pokémon
# (Game_FollowingPokemon), if there is one and it is out of its Poké Ball, is
# always the last link of the chain. It isn't stored in
# $PokemonGlobal.followers, so it never counts as "someone with you" for Surf,
# Fly and so on.
#===============================================================================
class Game_FollowerFactory
  attr_reader :last_update
  # @return [Game_FollowingPokemon, nil] the following Pokémon's event
  attr_reader :pokemon_event

  def initialize
    @events = []
    $PokemonGlobal.followers.each do |follower|
      @events.push(create_follower_object(follower))
    end
    @pokemon_event = nil
    @last_update = -1
  end

  #-----------------------------------------------------------------------------

  def add_follower(event, name = nil, common_event_id = nil)
    return if !event
    followers = $PokemonGlobal.followers
    if followers.any? { |data| data.original_map_id == $game_map.map_id && data.event_id == event.id }
      return   # Event is already dependent
    end
    eventData = FollowerData.new($game_map.map_id, event.id, event.name,
                                 $game_map.map_id, event.x, event.y, event.direction,
                                 event.character_name.clone, event.character_hue)
    eventData.name            = name
    eventData.common_event_id = common_event_id
    newEvent = create_follower_object(eventData)
    followers.push(eventData)
    @events.push(newEvent)
    @last_update += 1
  end

  def remove_follower_by_event(event)
    followers = $PokemonGlobal.followers
    map_id = $game_map.map_id
    followers.each_with_index do |follower, i|
      next if follower.current_map_id != map_id
      next if follower.original_map_id != event.map_id
      next if follower.event_id != event.id
      followers[i] = nil
      @events[i] = nil
      @last_update += 1
    end
    followers.compact!
    @events.compact!
  end

  def remove_follower_by_name(name)
    followers = $PokemonGlobal.followers
    followers.each_with_index do |follower, i|
      next if follower.name != name
      followers[i] = nil
      @events[i] = nil
      @last_update += 1
    end
    followers.compact!
    @events.compact!
  end

  def remove_all_followers
    $PokemonGlobal.followers.clear
    @events.clear
    @last_update += 1
  end

  # Sets (or, with nil, removes) the following Pokémon's event. Its sprite is
  # created or disposed on the next update.
  # @param event [Game_FollowingPokemon, nil]
  def pokemon_event=(event)
    return if @pokemon_event == event
    @pokemon_event = event
    @last_update += 1
  end

  # @return [Boolean] whether the following Pokémon is out and walking in the
  #   chain (not in its Poké Ball)
  def pokemon_in_chain?
    return !@pokemon_event.nil? && $PokemonGlobal.pokemon_follower&.out?
  end

  def get_follower_by_index(index = 0)
    @events.each_with_index { |event, i| return event if i == index }
    return nil
  end

  # @param name [String, Symbol] a follower's name, or :pokemon for the
  #   following Pokémon
  # @return [Game_Follower, nil]
  def get_follower_by_name(name)
    return @pokemon_event if name == :pokemon
    each_follower { |event, follower| return event if follower&.name == name }
    return nil
  end

  # Yields each follower in the chain, front to back, with its saved data. The
  # following Pokémon is included only while it is out of its Poké Ball.
  def each_follower
    chain.each { |event, follower| yield event, follower }
  end

  # Every follower event that needs a sprite, including the following Pokémon
  # while it is in its Poké Ball (so its ball animations can play).
  # @return [Array<Game_Follower>]
  def all_events
    ret = @events.compact
    ret.push(@pokemon_event) if @pokemon_event
    return ret
  end

  #-----------------------------------------------------------------------------

  def turn_followers
    leader = $game_player
    each_follower do |event, follower|
      event.turn_towards_leader(leader)
      follower.direction = event.direction
      leader = event
    end
  end

  def move_followers
    leader = $game_player
    each_follower do |event, follower|
      event.follow_leader(leader, false, (leader == $game_player))
      record_position(event, follower)
      leader = event
    end
  end

  # Places followers after the player is transferred to another map. Each one
  # is put on the free tile behind the character in front of it, facing the
  # same way, so they appear in line rather than popping out of the player.
  # Where there's no room, it is put on the player's tile and stays invisible
  # until the player starts moving.
  def map_transfer_followers
    FollowingPokemon.on_map_transfer
    leader = $game_player
    used_tiles = [[$game_player.x, $game_player.y]]
    each_follower do |event, follower|
      event.map = $game_map
      event.moveto($game_player.x, $game_player.y)
      event.direction = $game_player.direction
      event.opacity   = 255
      spot = event.spot_beside(leader, 10 - $game_player.direction, used_tiles)
      if spot
        event.moveto(spot[0], spot[1])
        event.direction = $game_player.direction
        used_tiles.push(spot)
        follower.invisible_after_transfer = false
        leader = event
      else
        follower.invisible_after_transfer = true
      end
      record_position(event, follower)
    end
  end

  def follow_into_door
    # Setting an event's move route also makes it start along that move route,
    # so we need to record all followers' current positions first before setting
    # any move routes
    follower_pos = []
    follower_pos.push([$game_player.map.map_id, $game_player.x, $game_player.y])
    each_follower do |event, follower|
      follower_pos.push([event.map.map_id, event.x, event.y])
    end
    # Calculate and set move route from each follower to player
    move_route = []
    chain.each_with_index do |pair, i|
      event = pair[0]
      leader = follower_pos[i]
      vector = $map_factory.getRelativePos(event.map.map_id, event.x, event.y,
                                           leader[0], leader[1], leader[2])
      if vector[0] != 0
        move_route.prepend((vector[0] > 0) ? PBMoveRoute::RIGHT : PBMoveRoute::LEFT)
      elsif vector[1] != 0
        move_route.prepend((vector[1] > 0) ? PBMoveRoute::DOWN : PBMoveRoute::UP)
      end
      pbMoveRoute(event, move_route + [PBMoveRoute::OPACITY, 0])
    end
  end

  # Used when coming out of a door.
  def hide_followers
    each_follower { |event, follower| event.opacity = 0 }
  end

  # Used when coming out of a door. Makes all followers invisible until the
  # player starts moving.
  def put_followers_on_player
    each_follower do |event, follower|
      event.moveto($game_player.x, $game_player.y)
      event.opacity = 255
      follower.invisible_after_transfer = true
      record_position(event, follower)
    end
  end

  #-----------------------------------------------------------------------------

  def update
    return if $game_temp.in_menu
    # The following Pokémon decides whether it should be out, and plays its
    # ball animations, even when there are no other followers
    FollowingPokemon.update
    members = chain
    if !members.empty?
      # Update all followers
      leader = $game_player
      player_moving = $game_player.moving? || $game_player.jumping?
      members.each do |event, follower|
        if follower.invisible_after_transfer && player_moving
          follower.invisible_after_transfer = false
          event.turn_towards_leader($game_player)
        end
        event.move_speed  = leader.move_speed
        event.transparent = !follower.visible?
        if $PokemonGlobal.ice_sliding
          event.straighten
          event.walk_anime = false
        else
          event.walk_anime = true
        end
        if event.jumping? || event.moving? || !player_moving
          event.update
        elsif !event.starting
          event.set_starting
          event.update
          event.clear_starting
        end
        # Never stand in anyone's way
        record_position(event, follower) if !player_moving && event.resolve_overlap
        follower.direction = event.direction
        leader = event
      end
    end
    # The following Pokémon still animates (e.g. its Poké Ball) while it isn't
    # in the chain
    @pokemon_event.update if @pokemon_event && !pokemon_in_chain?
    # Check event triggers
    if Input.trigger?(Input::USE) && !$game_temp.in_menu && !$game_temp.in_battle &&
       !$game_player.move_route_forcing && !$game_temp.message_window_showing &&
       !pbMapInterpreterRunning?
      # Get position of tile facing the player (diagonally ahead on sideways
      # stairs)
      step_x, step_y = $game_player.step_offset
      facing_tile = $map_factory.getRealTilePos($game_player.map.map_id,
                                                $game_player.x + step_x, $game_player.y + step_y)
      # Assumes player is 1x1 tile in size
      each_follower do |event, follower|
        next if !facing_tile || event.map.map_id != facing_tile[0] ||
                !event.at_coordinate?(facing_tile[1], facing_tile[2])   # Not on facing tile
        next if event.jumping? || !follower.visible?
        follower.interact(event)
        break
      end
    end
  end

  #-----------------------------------------------------------------------------

  private

  def create_follower_object(event_data)
    return Game_Follower.new(event_data)
  end

  # The followers in the chain, front to back: human followers, then the
  # following Pokémon if it is out.
  # @return [Array<Array(Game_Follower, FollowerData)>]
  def chain
    ret = []
    $PokemonGlobal.followers.each_with_index do |follower, i|
      ret.push([@events[i], follower]) if @events[i]
    end
    ret.push([@pokemon_event, $PokemonGlobal.pokemon_follower]) if pokemon_in_chain?
    return ret
  end

  # Saves a follower's position into its data (for saving the game).
  # @param event [Game_Follower]
  # @param follower [FollowerData]
  def record_position(event, follower)
    follower.x              = event.x
    follower.y              = event.y
    follower.current_map_id = event.map.map_id
    follower.direction      = event.direction
  end
end

#===============================================================================
#
#===============================================================================
class FollowerSprites
  def initialize(viewport)
    @viewport    = viewport
    @sprites     = []
    @last_update = nil
    @disposed    = false
  end

  def dispose
    return if @disposed
    @sprites.each { |sprite| sprite.dispose }
    @sprites.clear
    @disposed = true
  end

  def disposed?
    return @disposed
  end

  def refresh
    @sprites.each { |sprite| sprite.dispose }
    @sprites.clear
    $game_temp.followers.all_events.each do |event|
      @sprites.push(Sprite_Character.new(@viewport, event))
    end
  end

  def update
    if $game_temp.followers.last_update != @last_update
      refresh
      @last_update = $game_temp.followers.last_update
    end
    @sprites.each { |sprite| sprite.update }
  end
end

#===============================================================================
# Helper module for adding/removing/getting followers.
#===============================================================================
module Followers
  module_function

  # @param event_id [Integer] ID of the event on the current map to be added as a follower
  # @param name [String] identifier name of the follower to be added
  # @param common_event_id [Integer] ID of the Common Event triggered when interacting with this follower
  def add(event_id, name, common_event_id)
    $game_temp.followers.add_follower($game_map.events[event_id], name, common_event_id)
  end

  # @param event [Game_Event] map event to be added as a follower
  def add_event(event)
    $game_temp.followers.add_follower(event)
  end

  # @param name [String] identifier name of the follower to be removed
  def remove(name)
    $game_temp.followers.remove_follower_by_name(name)
  end

  # @param event [Game_Event] map event to be removed as a follower
  def remove_event(event)
    $game_temp.followers.remove_follower_by_event(event)
  end

  # Removes all followers.
  def clear
    $game_temp.followers.remove_all_followers
    pbDeregisterPartner rescue nil
  end

  # @param name [String, Symbol, nil] name of the follower to get, :pokemon for
  #   the following Pokémon, or nil for the first follower
  # @return [Game_Follower, nil] follower object
  def get(name = nil)
    return $game_temp.followers.get_follower_by_name(name) if name
    return $game_temp.followers.get_follower_by_index
  end

  def follow_into_door
    $game_temp.followers.follow_into_door
  end

  def hide_followers
    $game_temp.followers.hide_followers
  end

  def put_followers_on_player
    $game_temp.followers.put_followers_on_player
  end
end
