#===============================================================================
# Instances of this are stored in @realEvents.
#===============================================================================
class Game_Follower < Game_Event
  attr_writer :map

  def initialize(event_data)
    # Create RPG::Event to base self on
    rpg_event = RPG::Event.new(event_data.x, event_data.y)
    rpg_event.id = event_data.event_id
    rpg_event.name = event_data.event_name
    if event_data.common_event_id
      # Must setup common event list here and now
      common_event = Game_CommonEvent.new(event_data.common_event_id)
      rpg_event.pages[0].list = common_event.list
    end
    # Create self
    super(event_data.original_map_id, rpg_event, $map_factory.getMap(event_data.current_map_id))
    # Modify self
    self.character_name = event_data.character_name
    self.character_hue  = event_data.character_hue
    case event_data.direction
    when 2 then turn_down
    when 4 then turn_left
    when 6 then turn_right
    when 8 then turn_up
    end
  end

  def map_id
    return @map.map_id
  end

  #-----------------------------------------------------------------------------

  # Takes one straight step in direction, ignoring passability. The step is
  # exactly the one the leader took (not re-resolved for sideways stairs), so
  # self walks the leader's trail.
  # @param direction [Integer] 2, 4, 6 or 8
  def move_through(direction)
    delta_x = (direction == 6) ? 1 : (direction == 4) ? -1 : 0
    delta_y = (direction == 2) ? 1 : (direction == 8) ? -1 : 0
    return if !self.map.valid?(self.x + delta_x, self.y + delta_y)
    turn_generic(direction)
    step_to(delta_x, delta_y)
  end

  # Takes one diagonal step, as the leader does on sideways stairs, facing
  # sideways along the flight. Like move_through, passability is ignored
  # because the leader has just walked this way.
  # @param delta_x [Integer] -1 or 1
  # @param delta_y [Integer] -1 or 1
  def move_fancy_diagonal(delta_x, delta_y)
    return if !self.map.valid?(self.x + delta_x, self.y + delta_y)
    turn_generic((delta_x < 0) ? 4 : 6)
    step_to(delta_x, delta_y)
  end

  def move_fancy(direction)
    delta_x = (direction == 6) ? 1 : (direction == 4) ? -1 : 0
    delta_y = (direction == 2) ? 1 : (direction == 8) ? -1 : 0
    new_x = self.x + delta_x
    new_y = self.y + delta_y
    # Move if new position is the player's, or the new position is passable,
    # or self's current position is not passable
    if ($game_player.x == new_x && $game_player.y == new_y) ||
       location_passable?(new_x, new_y, 10 - direction) ||
       !location_passable?(self.x, self.y, direction)
      move_through(direction)
    end
  end

  def jump_fancy(direction, leader)
    delta_x = (direction == 6) ? 2 : (direction == 4) ? -2 : 0
    delta_y = (direction == 2) ? 2 : (direction == 8) ? -2 : 0
    half_delta_x = delta_x / 2
    half_delta_y = delta_y / 2
    if location_passable?(self.x + half_delta_x, self.y + half_delta_y, 10 - direction)
      # Can walk over the middle tile normally; just take two steps
      move_fancy(direction)
      move_fancy(direction)
    elsif location_passable?(self.x + delta_x, self.y + delta_y, 10 - direction)
      # Can't walk over the middle tile, but can walk over the end tile; jump over
      if location_passable?(self.x, self.y, direction)
        if leader.jumping?
          self.jump_speed = leader.jump_speed || 3
        else
          self.jump_speed = leader.move_speed || 3
          # This is halved because self has to jump 2 tiles in the time it takes
          # the leader to move one tile
          @jump_time /= 2
        end
        jump(delta_x, delta_y)
      else
        # self's current tile isn't passable; just take two steps ignoring passability
        move_through(direction)
        move_through(direction)
      end
    end
  end

  def fancy_moveto(new_x, new_y, leader)
    if self.x - new_x == 1 && self.y == new_y
      move_fancy(4)
    elsif self.x - new_x == -1 && self.y == new_y
      move_fancy(6)
    elsif self.x == new_x && self.y - new_y == 1
      move_fancy(8)
    elsif self.x == new_x && self.y - new_y == -1
      move_fancy(2)
    elsif self.x - new_x == 2 && self.y == new_y
      jump_fancy(4, leader)
    elsif self.x - new_x == -2 && self.y == new_y
      jump_fancy(6, leader)
    elsif self.x == new_x && self.y - new_y == 2
      jump_fancy(8, leader)
    elsif self.x == new_x && self.y - new_y == -2
      jump_fancy(2, leader)
    elsif (self.x - new_x).abs == 1 && (self.y - new_y).abs == 1
      move_fancy_diagonal(new_x - self.x, new_y - self.y)
    elsif self.x != new_x || self.y != new_y
      moveto(new_x, new_y)
    end
  end

  # Ceases all movement immediately. Used when the leader wants to move another
  # tile but self hasn't quite finished its previous movement yet.
  def end_movement
    @x = x % self.map.width
    @y = y % self.map.height
    @real_x = @x * Game_Map::REAL_RES_X
    @real_y = @y * Game_Map::REAL_RES_Y
    @move_timer = nil
    @jump_timer = nil
    @jump_peak = 0
    @jump_distance = 0
    @jump_fraction = 0
    @jumping_on_spot = false
  end

  #-----------------------------------------------------------------------------

  def turn_towards_leader(leader)
    pbTurnTowardEvent(self, leader)
  end

  # Moves self along its leader's trail. Called when the leader starts a step
  # or jump. The follower takes the step its leader just left (from the
  # leader's step_history), so it copies diagonal stair steps, ledge jumps and
  # ice slides exactly. If self has fallen too far behind to reach that tile in
  # one step (e.g. after a forced move route), it first catches up to the
  # previous tile of the trail.
  # @param leader [Game_Character] the player or the follower in front
  # @param instant [Boolean] whether to place self without walking
  # @param leaderIsTrueLeader [Boolean] whether leader is the player
  def follow_leader(leader, instant = false, leaderIsTrueLeader = true)
    return if @move_route_forcing
    end_movement
    maps_connected = $map_factory.areConnected?(leader.map.map_id, self.map.map_id)
    target = nil
    # Get the target tile that self wants to move to
    if maps_connected
      # Walk the leader's trail: the tile its last step started from. If there
      # is none (e.g. the leader was just placed), use the tile behind it.
      target = trail_target(leader)
      catch_up_along_trail(leader, target) if target && !instant
      target = fallback_target(leader) if !target
      target = [leader.map.map_id, leader.x, leader.y] if !target
    else
      # Map transfer to an unconnected map
      target = [leader.map.map_id, leader.x, leader.y]
    end
    # Move self to the target
    rehome_to_map(target[0])
    if instant || !maps_connected
      moveto(target[1], target[2])
    else
      fancy_moveto(target[1], target[2], leader)
    end
  end

  # Whether self could reach the tile in one leader step (a step, a diagonal
  # stair step or a two-tile jump).
  # @param map_id [Integer]
  # @param x [Integer]
  # @param y [Integer]
  # @return [Boolean]
  def within_one_step?(map_id, x, y)
    return false if !$map_factory.areConnected?(map_id, self.map.map_id)
    vector = $map_factory.getRelativePos(self.map.map_id, self.x, self.y, map_id, x, y)
    return false if !vector
    dx = vector[0].abs
    dy = vector[1].abs
    return (dx <= 1 && dy <= 1) || (dx == 0 && dy <= 2) || (dy == 0 && dx <= 2)
  end

  # Moves self out of the way if something else is standing on its tile: an
  # NPC that walked into it, a boulder pushed onto it, or the player (moved
  # there by a move route). Self steps to a free neighbouring tile, sideways
  # first, so it never blocks anyone. Does nothing while self is busy, hidden
  # or on sideways stairs.
  # @return [Boolean] whether self moved
  def resolve_overlap
    return false if moving? || jumping? || @move_route_forcing || @transparent
    return false if on_stairs?
    return false if !tile_occupied?(self.map.map_id, self.x, self.y, true)
    sidestep_directions.each do |dir|
      dx = (dir == 6) ? 1 : (dir == 4) ? -1 : 0
      dy = (dir == 2) ? 1 : (dir == 8) ? -1 : 0
      new_x = self.x + dx
      new_y = self.y + dy
      next if !self.map.valid?(new_x, new_y)
      next if !location_passable?(new_x, new_y, 10 - dir)
      next if tile_occupied?(self.map.map_id, new_x, new_y)
      next if stairs_at(new_x, new_y)
      move_through(dir)
      return true
    end
    return false
  end

  # A free tile next to leader, on leader's map, that self could stand on: one
  # the leader could step to in direction dir, that isn't a ledge or sideways
  # stairs and that nobody else stands on.
  # @param leader [Game_Character]
  # @param dir [Integer] direction from leader to the tile
  # @param used_tiles [Array<Array<Integer>>] [x, y] tiles that count as taken
  # @return [Array<Integer>, nil] [x, y], or nil if the tile isn't free
  def spot_beside(leader, dir, used_tiles = [])
    map = leader.map
    dx = (dir == 6) ? 1 : (dir == 4) ? -1 : 0
    dy = (dir == 2) ? 1 : (dir == 8) ? -1 : 0
    x = leader.x + dx
    y = leader.y + dy
    return nil if !map.valid?(x, y) || used_tiles.include?([x, y])
    return nil if !map.passable?(leader.x, leader.y, dir) || !map.passable?(x, y, 10 - dir)
    tag = map.terrain_tag(x, y)
    return nil if tag.ledge || tag.stairs?
    return nil if tile_occupied?(map.map_id, x, y)
    return [x, y]
  end

  # Whether another character (not self) stands on a tile: the player, or a
  # visible map event that isn't "through".
  # @param map_id [Integer]
  # @param x [Integer]
  # @param y [Integer]
  # @param include_player [Boolean] whether the player counts
  # @return [Boolean]
  def tile_occupied?(map_id, x, y, include_player = true)
    if include_player && $game_player.map.map_id == map_id &&
       $game_player.x == x && $game_player.y == y
      return true
    end
    map = (map_id == self.map.map_id) ? self.map : $map_factory.getMapNoAdd(map_id)
    return false if !map
    map.events.each_value do |event|
      next if event == self || event.through || !event.at_coordinate?(x, y)
      next if event.character_name == "" && event.tile_id <= 0
      return true
    end
    return false
  end

  #-----------------------------------------------------------------------------

  private

  # Moves self onto another (connected) map without changing where it is on
  # screen. Coordinates may be outside the new map's bounds until the step that
  # crosses the edge finishes.
  # @param map_id [Integer]
  def rehome_to_map(map_id)
    return if self.map.map_id == map_id
    vector = $map_factory.getRelativePos(map_id, 0, 0, self.map.map_id, @x, @y)
    @map = $map_factory.getMap(map_id)
    # NOTE: Can't use moveto because vector is outside the boundaries of the
    #       map, and moveto doesn't allow setting invalid coordinates.
    @x = vector[0]
    @y = vector[1]
    @real_x = @x * Game_Map::REAL_RES_X
    @real_y = @y * Game_Map::REAL_RES_Y
  end

  # If self can't reach target in one step, puts it on the tile of the
  # leader's trail just before target, so that it then walks the last step
  # rather than teleporting all the way.
  # @param leader [Game_Character]
  # @param target [Array<Integer>] [map_id, x, y]
  def catch_up_along_trail(leader, target)
    return if within_one_step?(*target)
    previous = leader.step_history[-2]
    return if !previous
    return if !$map_factory.areConnected?(previous[:map_id], target[0])
    rehome_to_map(previous[:map_id])
    moveto(previous[:x], previous[:y])
  end

  # The tile behind the leader (or, past a ledge, the tile the leader jumped
  # from), for when the leader has no trail to follow. Tiles with an NPC on
  # them are skipped in favour of the leader's other sides.
  # @param leader [Game_Character]
  # @return [Array<Integer>, nil] [map_id, x, y]
  def fallback_target(leader)
    behind_direction = 10 - leader.direction
    directions = [behind_direction] + ([2, 4, 6, 8] - [behind_direction, leader.direction])
    directions.each do |dir|
      target = $map_factory.getFacingTile(dir, leader)
      next if !target
      if $map_factory.getTerrainTag(target[0], target[1], target[2]).ledge
        # Get the tile above the ledge (where the leader jumped from)
        target = $map_factory.getFacingTileFromPos(target[0], target[1], target[2], dir)
        next if !target
      end
      next if tile_occupied?(target[0], target[1], target[2], false)
      return target
    end
    return nil
  end

  # The directions to try when stepping aside: sideways first, then backwards,
  # then forwards.
  # @return [Array<Integer>]
  def sidestep_directions
    case @direction
    when 2, 8 then return [4, 6, 10 - @direction, @direction]
    else           return [2, 8, 10 - @direction, @direction]
    end
  end

  # The tile the leader's last step or jump started from, if it is close enough
  # to follow by walking (or jumping, for ledges). This follows the leader's
  # actual path, e.g. diagonally along sideways stairs, where the tile behind
  # the leader's facing is wrong.
  # @param leader [Game_Character]
  # @return [Array<Integer>, nil] [map_id, x, y], or nil to fall back to the
  #   tile behind the leader's facing
  def trail_target(leader)
    from = leader.last_step_from
    return nil if !from || !$map_factory.areConnected?(from[0], leader.map.map_id)
    vector = $map_factory.getRelativePos(from[0], from[1], from[2], leader.map.map_id, leader.x, leader.y)
    return nil if !vector || vector == [0, 0] || vector[0].abs > 2 || vector[1].abs > 2
    return from
  end

  def location_passable?(x, y, direction)
    this_map = self.map
    return false if !this_map || !this_map.valid?(x, y)
    return true if @through
    passed_tile_checks = false
    bit = (1 << ((direction / 2) - 1)) & 0x0f
    # Check all events for ones using tiles as graphics, and see if they're passable
    this_map.events.each_value do |event|
      next if event.tile_id < 0 || event.through || !event.at_coordinate?(x, y)
      tile_data = GameData::TerrainTag.try_get(this_map.terrain_tags[event.tile_id])
      next if tile_data.ignore_passability
      next if tile_data.bridge && $PokemonGlobal.bridge == 0
      return false if tile_data.ledge
      passage = this_map.passages[event.tile_id] || 0
      return false if passage & bit != 0
      passed_tile_checks = true if (tile_data.bridge && $PokemonGlobal.bridge > 0) ||
                                   (this_map.priorities[event.tile_id] || -1) == 0
      break if passed_tile_checks
    end
    # Check if tiles at (x, y) allow passage for followe
    if !passed_tile_checks
      [2, 1, 0].each do |i|
        tile_id = this_map.data[x, y, i] || 0
        next if tile_id == 0
        tile_data = GameData::TerrainTag.try_get(this_map.terrain_tags[tile_id])
        next if tile_data.ignore_passability
        next if tile_data.bridge && $PokemonGlobal.bridge == 0
        return false if tile_data.ledge
        passage = this_map.passages[tile_id] || 0
        return false if passage & bit != 0
        break if tile_data.bridge && $PokemonGlobal.bridge > 0
        break if (this_map.priorities[tile_id] || -1) == 0
      end
    end
    # Check all events on the map to see if any are in the way
    this_map.events.each_value do |event|
      next if !event.at_coordinate?(x, y)
      return false if !event.through && event.character_name != ""
    end
    return true
  end
end
