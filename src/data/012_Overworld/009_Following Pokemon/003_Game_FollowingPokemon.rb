#===============================================================================
# Following Pokémon: the event that walks behind the player.
#===============================================================================
# A Game_Follower, so it follows its leader (the player) exactly as other
# followers do: along the leader's step history, over ledges, up and down
# sideways stairs, across connected map edges and through warps. On top of
# that it:
#   * shows the overworld sprite of a party Pokémon (see FollowingPokemon),
#   * is drawn a little further back if its sprite is big (size_category),
#   * floats and keeps animating if it's airborne,
#   * plays Poké Ball animations as it comes out and goes back in.
#===============================================================================
class Game_FollowingPokemon < Game_Follower
  # Seconds a Poké Ball animation (9 frames at 20 frames per second) lasts.
  BALL_ANIMATION_DURATION = 0.45

  # @return [Pokemon, nil] the Pokémon this event currently shows
  attr_reader :pokemon

  # @param event_data [PokemonFollowerData]
  def initialize(event_data)
    super(event_data)
    @pokemon     = nil
    @airborne    = false
    @appear_at   = nil
    @vanish_at   = nil
    @busy_until  = nil
    @float_start = System.uptime
    apply_pokemon_settings
  end

  # Re-applies the Pokémon's settings after the event's page is refreshed
  # (which resets them to the page's).
  def refresh
    super
    apply_pokemon_settings
  end

  #-----------------------------------------------------------------------------
  # Which Pokémon is shown
  #-----------------------------------------------------------------------------

  # Shows pkmn's overworld sprite, or nothing if pkmn is nil.
  # @param pkmn [Pokemon, nil]
  def pokemon=(pkmn)
    @pokemon = pkmn
    @airborne = FollowingPokemon.airborne?(pkmn)
    self.character_name = FollowingPokemon.sprite_name(pkmn) || ""
    apply_pokemon_settings
  end

  # @return [Boolean] whether the shown Pokémon flies or floats, so it bobs in
  #   the air, isn't hidden by tall grass and keeps animating on ice
  def airborne?
    return @airborne
  end

  # @return [Symbol] :small, :medium or :large, from SIZE_OVERRIDES or else the
  #   width of the sprite's frames
  def size_category
    return FollowingPokemon.size_category(@pokemon, (@sprite_size) ? @sprite_size[0] : nil)
  end

  # The tint for the shown Pokémon's status problem.
  # @return [Tone, nil]
  def status_tone
    return nil if !FollowingPokemon::APPLY_STATUS_TONES || !@pokemon
    values = FollowingPokemon::STATUS_TONES[@pokemon.status]
    return (values) ? Tone.new(*values) : nil
  end

  #-----------------------------------------------------------------------------
  # Poké Ball animations
  #-----------------------------------------------------------------------------

  # Plays the Poké Ball "out" animation where self stands, and makes self
  # appear partway through it.
  def play_ball_out
    id = FollowingPokemon.animation_id(FollowingPokemon::ANIMATION_BALL_OUT)
    now = System.uptime
    @vanish_at  = nil
    @appear_at  = now + ((id) ? FollowingPokemon::BALL_OUT_APPEAR_TIME : 0)
    @busy_until = now + ((id) ? BALL_ANIMATION_DURATION : 0)
    self.animation_id = id if id
  end

  # Plays the Poké Ball "in" animation where self stands, and makes self
  # disappear partway through it.
  def play_ball_in
    id = FollowingPokemon.animation_id(FollowingPokemon::ANIMATION_BALL_IN)
    now = System.uptime
    @appear_at  = nil
    @vanish_at  = now + ((id) ? FollowingPokemon::BALL_IN_VANISH_TIME : 0)
    @busy_until = now + ((id) ? BALL_ANIMATION_DURATION : 0)
    self.animation_id = id if id
  end

  # Ends any Poké Ball animation timing at once (e.g. on a map transfer).
  def stop_ball_animation
    @appear_at  = nil
    @vanish_at  = nil
    @busy_until = nil
  end

  # @return [Boolean] whether a Poké Ball animation is still playing
  def busy?
    return !@busy_until.nil? && System.uptime < @busy_until
  end

  # Self is invisible while it's in its Poké Ball, and is shown/hidden partway
  # through the Poké Ball animations.
  def transparent
    now = System.uptime
    if @vanish_at   # Going back into its Poké Ball
      return now >= @vanish_at || @transparent
    end
    return true if @appear_at && now < @appear_at
    return true if !$PokemonGlobal.pokemon_follower.out?
    return super
  end

  #-----------------------------------------------------------------------------
  # Drawing
  #-----------------------------------------------------------------------------

  # Airborne Pokémon (flying, levitating or floating, see
  # FollowingPokemon.airborne?) are drawn above tall grass, so neither bush nor
  # deep bush tiles hide any of them. This is checked live, so a depth worked out
  # for a previous Pokémon (or before loading a save) never applies.
  # @return [Integer]
  def bush_depth
    return 0 if airborne?
    return super
  end

  def calculate_bush_depth
    super
    @bush_depth = 0 if airborne?
  end

  # Airborne Pokémon don't rustle the grass they fly over, and nothing rustles
  # it while the Pokémon is in its Poké Ball.
  # @return [Boolean]
  def rustles_grass?
    return false if airborne? || transparent
    return super
  end

  # Undoes anything a door transfer did to how self looks: makes it fully opaque
  # again and drops any move route it was still forced along (e.g.
  # Followers.follow_into_door's, which ends by making it invisible). Called
  # whenever it's placed after a map transfer or sent out of its Poké Ball, so it
  # never comes out invisible.
  def reset_appearance
    @opacity = 255
    return if !@move_route_forcing
    @move_route_forcing = false
    if @original_move_route
      @move_route          = @original_move_route
      @move_route_index    = @original_move_route_index
      @original_move_route = nil
    end
  end

  def screen_x
    ret = super
    offset = size_offset
    return ret if offset == 0
    case @direction
    when 4 then ret += offset if self.map.passable?(self.x, self.y, 6)
    when 6 then ret -= offset if self.map.passable?(self.x, self.y, 4)
    end
    return ret
  end

  def screen_y
    ret = super
    offset = size_offset
    if offset != 0
      case @direction
      when 2 then ret -= offset if self.map.passable?(self.x, self.y, 8)
      when 8 then ret += offset if self.map.passable?(self.x, self.y, 2)
      end
    end
    ret -= float_height
    return ret
  end

  # Big Pokémon are drawn over whatever is just in front of their tile, like
  # the player is.
  def screen_z(height = 0)
    return super + 1
  end

  #-----------------------------------------------------------------------------
  # Updating
  #-----------------------------------------------------------------------------

  def update
    now = System.uptime
    @appear_at = nil if @appear_at && now >= @appear_at
    if @vanish_at && now >= @vanish_at && !busy?
      @vanish_at = nil   # Fully in its Poké Ball now; out? says it's hidden
    end
    @busy_until = nil if @busy_until && now >= @busy_until
    super
  end

  # Airborne Pokémon don't kick up dust when landing.
  def update_move
    return Game_Character.instance_method(:update_move).bind(self).call if @airborne
    super
  end

  # Airborne Pokémon keep flapping/floating while sliding on ice.
  def walk_anime=(value)
    value = true if @airborne
    super(value)
  end

  def straighten
    return if @airborne && $PokemonGlobal.ice_sliding
    super
  end

  #-----------------------------------------------------------------------------

  private

  def apply_pokemon_settings
    @step_anime  = @airborne   # Airborne Pokémon animate while idle
    @walk_anime  = true
    @direction_fix = false
    calculate_bush_depth
  end

  # @return [Integer] pixels to draw self back from its leader, by size
  def size_offset
    return FollowingPokemon::SIZE_OFFSETS[size_category] || 0
  end

  # @return [Integer] pixels an airborne Pokémon is lifted by its bob
  def float_height
    return 0 if !@airborne || jumping?
    period = FollowingPokemon::FLOAT_DURATION
    phase = ((System.uptime - @float_start) % period) / period
    return ((1 - Math.cos(phase * 2 * Math::PI)) * FollowingPokemon::FLOAT_HEIGHT / 2.0).round
  end
end
