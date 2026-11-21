#===============================================================================
# Following Pokémon: deciding which Pokémon follows, and when.
#===============================================================================
# The first party Pokémon that isn't an egg and hasn't fainted walks behind
# the player, unless something keeps it in its Poké Ball (see hide_reasons).
# Every frame, update checks the party and those reasons: whenever the
# Pokémon comes out or goes back in (or the lead Pokémon changes), its Poké
# Ball animation plays.
#
# Script commands for events:
#   FollowingPokemon.toggle(false)        Turn the following Pokémon off
#   FollowingPokemon.toggle(true)         ...and back on
#   FollowingPokemon.hide(:my_reason)     Put it in its ball for a while
#   FollowingPokemon.show(:my_reason)     ...and let it back out
#   FollowingPokemon.emote(:heart)        Show an emote bubble over it
#   FollowingPokemon.move_route([...])    Give it a move route
#   FollowingPokemon.talk                 Talk to it
# In Tiled event scripts, the following Pokémon is also the character
# `pokemon_follower` (e.g. for move routes and Show Animation).
#===============================================================================
module FollowingPokemon
  # Reasons for hiding that don't play the Poké Ball animation.
  SILENT_HIDE_REASONS = [:player_hidden, :no_pokemon]
  # Seconds emote(..., true) waits: long enough to see the bubble pop up.
  EMOTE_WAIT = 0.6

  module_function

  #-----------------------------------------------------------------------------
  # Basics
  #-----------------------------------------------------------------------------

  # @return [PokemonFollowerData, nil] the saved state
  def data
    return $PokemonGlobal&.pokemon_follower
  end

  # @return [Game_FollowingPokemon, nil] the following Pokémon's event
  def event
    return $game_temp&.followers&.pokemon_event
  end

  # @return [Pokemon, nil] the Pokémon that should follow the player: the first
  #   party Pokémon that isn't an egg and hasn't fainted
  def pokemon
    return nil if !$player
    return $player.party.find { |pkmn| pkmn && !pkmn.egg? && !pkmn.fainted? }
  end

  # @return [Boolean] whether the Pokémon is out of its Poké Ball, walking
  #   behind the player
  def out?
    return data&.out? || false
  end

  # @return [Boolean] whether the following Pokémon is out and can be seen
  #   (e.g. talked to)
  def active?
    return out? && !event.nil? && !event.transparent
  end

  # What a Pokémon looks like as a follower. When this changes for the
  # Pokémon that's out (e.g. it evolves or changes form), its sprite changes.
  # @param pkmn [Pokemon, nil]
  # @return [Array, nil]
  def signature(pkmn)
    return nil if !pkmn
    return [pkmn.personalID, pkmn.species, pkmn.form, pkmn.shiny?, pkmn.gender, pkmn.status]
  end

  #-----------------------------------------------------------------------------
  # Appearance
  #-----------------------------------------------------------------------------

  # The overworld sprite of a Pokémon, as a file name in Graphics/Characters.
  # @param pkmn [Pokemon, nil]
  # @return [String, nil] e.g. "Followers/PIKACHU" or "Followers shiny/PIKACHU",
  #   or nil if there's no sprite (not even the fallback 000)
  def sprite_name(pkmn)
    return nil if !pkmn
    path = GameData::Species.check_graphic_file("Graphics/Characters/", pkmn.species,
                                                pkmn.form, pkmn.gender, pkmn.shiny?,
                                                false, SPRITE_FOLDER)
    return nil if !path
    return path.sub(/\A.*?Graphics\/Characters\//i, "").sub(/\.(png|gif)\z/i, "")
  end

  # Whether a Pokémon flies, levitates or floats: it's Flying type, has
  # Levitate, its species has one of AIRBORNE_FLAGS, or its battle sprite is
  # drawn in the air. Airborne Pokémon bob in the air, and tall grass (bush and
  # deep bush tiles) neither hides them nor rustles under them.
  # @param pkmn [Pokemon, nil]
  # @return [Boolean]
  def airborne?(pkmn)
    return false if !pkmn
    return true if pkmn.hasType?(:FLYING) || pkmn.hasAbility?(:LEVITATE)
    species_data = GameData::Species.get_species_form(pkmn.species, pkmn.form)
    return true if AIRBORNE_FLAGS.any? { |flag| species_data.has_flag?(flag) }
    metrics = GameData::SpeciesMetrics.get_species_form(pkmn.species, pkmn.form)
    return (metrics&.front_sprite_altitude || 0) > 0
  end

  # The size of a Pokémon's overworld sprite: SIZE_OVERRIDES if it's listed
  # there (by "SPECIES_form" or species), otherwise from the width of one frame
  # of its sprite.
  # @param pkmn [Pokemon, nil]
  # @param frame_width [Integer, nil] width of one frame of its sprite in
  #   pixels, or nil if not known yet
  # @return [Symbol] :small, :medium or :large
  def size_category(pkmn, frame_width)
    if pkmn
      form_key = (pkmn.form > 0) ? :"#{pkmn.species}_#{pkmn.form}" : nil
      return SIZE_OVERRIDES[form_key] if form_key && SIZE_OVERRIDES[form_key]
      return SIZE_OVERRIDES[pkmn.species] if SIZE_OVERRIDES[pkmn.species]
    end
    return :small if !frame_width || frame_width <= SMALL_FRAME_WIDTH
    return :medium if frame_width <= MEDIUM_FRAME_WIDTH
    return :large
  end

  # The ID of an animation in Data/Animations.rxdata, found by name.
  # @param name [String, Symbol] the animation's name, or :exclaim for the
  #   exclamation bubble
  # @return [Integer, nil] nil if there's no such animation
  def animation_id(name)
    return Settings::EXCLAMATION_ANIMATION_ID if name == :exclaim
    return nil if !$data_animations
    if @animation_ids.nil? || @animation_ids_source != $data_animations.object_id
      @animation_ids = {}
      @animation_ids_source = $data_animations.object_id
      $data_animations.each_with_index do |anim, id|
        next if !anim || anim.name.nil? || anim.name.empty?
        @animation_ids[anim.name] ||= id
      end
    end
    return @animation_ids[name]
  end

  #-----------------------------------------------------------------------------
  # When to follow
  #-----------------------------------------------------------------------------

  # Every reason the Pokémon should currently be in its Poké Ball. It follows
  # the player only if there are none.
  # @param pkmn [Pokemon, nil] the Pokémon that would follow
  # @return [Array<Symbol>]
  def hide_reasons(pkmn = pokemon)
    ret = []
    ret.push(:no_pokemon) if !pkmn
    ret.push(:option_off) if $PokemonSystem && $PokemonSystem.following_pokemon != 0
    ret.push(:toggled_off) if data&.toggled_off
    ret.concat(data.hide_reasons) if data
    ret.push(:map_flag) if $game_map&.metadata&.has_flag?(MAP_FLAG_HIDE)
    ret.push(:human_follower) if $PokemonGlobal && $PokemonGlobal.followers.length > 0
    ret.push(:surfing) if $PokemonGlobal&.surfing || $game_temp&.ending_surf
    ret.push(:diving) if $PokemonGlobal&.diving
    ret.push(:cycling) if HIDE_WHEN_CYCLING && $PokemonGlobal&.bicycle
    ret.push(:too_big_indoors) if too_big_indoors?(pkmn)
    # Door events hide the player for a moment while everyone walks through the
    # door, so only an invisible player outside of events counts
    ret.push(:player_hidden) if $game_player&.transparent && !pbMapInterpreterRunning?
    return ret.uniq
  end

  # @param pkmn [Pokemon, nil]
  # @return [Boolean] whether pkmn is too tall to follow on this (indoor) map
  def too_big_indoors?(pkmn)
    return false if !pkmn || MAX_INDOOR_HEIGHT.nil?
    metadata = $game_map&.metadata
    return false if metadata.nil? || metadata.outdoor_map
    return false if metadata.has_flag?(MAP_FLAG_SHOW)
    return false if $PokemonEncounters&.encounter_possible_here?
    height = GameData::Species.get_species_form(pkmn.species, pkmn.form).height
    return height / 10.0 > MAX_INDOOR_HEIGHT
  end

  #-----------------------------------------------------------------------------
  # Updating
  #-----------------------------------------------------------------------------

  # Called every frame (from Game_FollowerFactory#update). Creates the
  # following Pokémon's event, keeps it showing the right Pokémon, and sends it
  # out or recalls it as hide_reasons change.
  def update
    return if !$player || !$PokemonGlobal || !$game_map
    pkmn = pokemon
    ev = ensure_event(pkmn)
    return if !ev || ev.busy?
    # A Pokémon Center nurse has finished healing
    data.hide_reasons.delete(:pokemon_center) if !pbMapInterpreterRunning?
    reasons = hide_reasons(pkmn)
    if data.out?
      if !reasons.empty?
        recall((reasons & SILENT_HIDE_REASONS).empty?)
      elsif data.personal_id != pkmn.personalID
        recall(true)   # The lead Pokémon changed; the new one comes out next
      elsif data.signature != signature(pkmn)
        ev.pokemon = pkmn   # Evolved, changed form, got a status problem, etc.
        data.signature = signature(pkmn)
        SpriteCache.update
      end
    elsif reasons.empty? && can_send_out_now?
      send_out(pkmn, true)
    end
  end

  # Applies hide_reasons at once rather than waiting for the player to stop
  # moving (e.g. after a script changes something).
  # @param anim [Boolean] whether to play the Poké Ball animations
  def refresh(anim = true)
    pkmn = pokemon
    ev = ensure_event(pkmn)
    return if !ev
    reasons = hide_reasons(pkmn)
    if reasons.empty?
      if !data.out?
        send_out(pkmn, anim)
      elsif data.personal_id != pkmn.personalID || data.signature != signature(pkmn)
        ev.pokemon = pkmn
        data.personal_id = pkmn.personalID
        data.signature = signature(pkmn)
      end
    elsif data.out?
      recall(anim)
    end
    SpriteCache.update
  end

  # Called just before the map's sprites are created (e.g. when a saved game is
  # loaded). Creates the following Pokémon's event now if it doesn't exist yet,
  # rather than on the first update, so that its sprite is created along with
  # all the others and it's already there as the screen fades in (instead of
  # appearing only once the fade-in has finished).
  def prepare_for_spritesets
    return if !$player || !$PokemonGlobal || !$game_map || !$game_temp
    ev = ensure_event(pokemon)
    ev&.recalculate_should_update
  end

  # Called just before followers are placed after the player is transferred
  # to another map. The transfer itself never plays a Poké Ball animation: a
  # Pokémon that was out stays out (on the new map) unless something there
  # keeps it in, in which case it is put away silently. A Pokémon that was in
  # its Poké Ball comes out once the player arrives (see update).
  def on_map_transfer
    ev = event
    return if !ev
    ev.stop_ball_animation
    ev.reset_appearance
    ev.map = $game_map
    data.out = false if data.out? && !hide_reasons.empty?
    if !data.out?
      ev.moveto($game_player.x, $game_player.y)
      record_position(ev)
    end
  end

  # Sends the Pokémon out of its Poké Ball onto a free tile next to the
  # player (behind them, if possible).
  # @param pkmn [Pokemon]
  # @param anim [Boolean] whether to play the Poké Ball animation
  def send_out(pkmn, anim = true)
    ev = event
    return if !ev || !pkmn
    ev.reset_appearance
    ev.pokemon = pkmn
    data.personal_id = pkmn.personalID
    data.signature = signature(pkmn)
    place_near_player(ev)
    data.out = true
    (anim) ? ev.play_ball_out : ev.stop_ball_animation
    SpriteCache.update
  end

  # Puts the Pokémon back into its Poké Ball.
  # @param anim [Boolean] whether to play the Poké Ball animation
  def recall(anim = true)
    ev = event
    return if !ev || !data.out?
    data.out = false
    (anim) ? ev.play_ball_in : ev.stop_ball_animation
  end

  # Recalls the Pokémon (if it's out) and waits for its Poké Ball animation to
  # finish. For use before something that should happen with it put away,
  # e.g. starting to surf or flying.
  # @param reason [Symbol, nil] a hide reason to add, keeping it in its ball
  #   until show(reason) is called
  def recall_and_wait(reason = nil)
    data.hide_reasons.push(reason) if reason && !data.hide_reasons.include?(reason)
    return if !out?
    recall(active?)
    pbWait(Game_FollowingPokemon::BALL_ANIMATION_DURATION) if event&.busy?
  end

  # Removes a hide reason added by recall_and_wait without sending the
  # Pokémon out straight away: it comes out (with its Poké Ball animation) as
  # soon as the player is standing still.
  # @param reason [Symbol]
  def release(reason)
    data.hide_reasons.delete(reason)
  end

  #-----------------------------------------------------------------------------
  # Script commands
  #-----------------------------------------------------------------------------

  # Turns the following Pokémon on or off (it's on unless turned off). This is
  # separate from the player's Options setting; both must be on.
  # @param value [Boolean, nil] true for on, false for off, nil to switch
  # @param anim [Boolean] whether to play the Poké Ball animation
  def toggle(value = nil, anim = true)
    value = data.toggled_off if value.nil?
    data.toggled_off = !value
    refresh(anim)
  end

  # Keeps the Pokémon in its Poké Ball until show(reason) is called. Several
  # reasons can apply at once.
  # @param reason [Symbol]
  # @param anim [Boolean] whether to play the Poké Ball animation
  def hide(reason = :event, anim = true)
    data.hide_reasons.push(reason) if !data.hide_reasons.include?(reason)
    refresh(anim)
  end

  # Undoes hide(reason).
  # @param reason [Symbol]
  # @param anim [Boolean] whether to play the Poké Ball animation
  def show(reason = :event, anim = true)
    data.hide_reasons.delete(reason)
    refresh(anim)
  end

  # Shows an emote bubble over the following Pokémon.
  # @param emote [Symbol] a key of EMOTES, or :exclaim
  # @param wait [Boolean] whether to wait for the bubble to finish
  # @return [Boolean] whether the bubble was shown
  def emote(emote, wait = false)
    return false if !active?
    id = animation_id((emote == :exclaim) ? :exclaim : EMOTES[emote])
    return false if !id
    event.animation_id = id
    pbWait(EMOTE_WAIT) if wait
    return true
  end

  # Gives the following Pokémon a move route (see pbMoveRoute).
  # @param commands [Array] PBMoveRoute commands and their parameters
  # @param wait [Boolean] whether to wait for the route to finish
  # @return [RPG::MoveRoute, nil]
  def move_route(commands, wait = false)
    return nil if !active?
    return pbMoveRoute(event, commands, wait)
  end

  #-----------------------------------------------------------------------------

  # Creates the following Pokémon's event if there's a Pokémon to follow, or
  # removes it once there isn't one and it's back in its ball.
  # @param pkmn [Pokemon, nil]
  # @return [Game_FollowingPokemon, nil]
  def ensure_event(pkmn)
    factory = $game_temp.followers
    ev = factory.pokemon_event
    if !pkmn && ev && !data.out? && !ev.busy?
      factory.pokemon_event = nil
      return nil
    end
    return ev if ev || !pkmn
    # Put the event where it was saved, if that's on or next to this map
    if data.current_map_id != $game_map.map_id &&
       !$map_factory.areConnected?(data.current_map_id, $game_map.map_id)
      data.current_map_id = $game_map.map_id
      data.x = $game_player.x
      data.y = $game_player.y
      data.direction = $game_player.direction
      data.out = false
    end
    ev = Game_FollowingPokemon.new(data)
    ev.pokemon = (data.out?) ? pkmn : nil
    if data.out?
      data.personal_id = pkmn.personalID
      data.signature = signature(pkmn)
    end
    factory.pokemon_event = ev
    SpriteCache.update
    return ev
  end

  # @return [Boolean] whether now is a good time for the Pokémon to come out
  #   by itself: the player is standing still and nothing is going on
  def can_send_out_now?
    return false if $game_temp.player_transferring || $game_temp.in_menu
    return false if $game_player.moving? || $game_player.jumping?
    return false if $game_player.move_route_forcing
    return false if pbMapInterpreterRunning? || $game_temp.message_window_showing
    return true
  end

  # Puts the event on a free tile next to the player: behind them if
  # possible, then beside, then in front. If there's no room, it stands on the
  # player's tile, invisible until the player moves.
  # @param ev [Game_FollowingPokemon]
  def place_near_player(ev)
    ev.map = $game_map
    behind = 10 - $game_player.direction
    directions = [behind] + ([4, 6, 2, 8] - [behind, $game_player.direction]) + [$game_player.direction]
    spot = nil
    directions.each do |dir|
      spot = ev.spot_beside($game_player, dir)
      break if spot
    end
    if spot
      ev.moveto(spot[0], spot[1])
      ev.turn_towards_leader($game_player)
      data.invisible_after_transfer = false
    else
      ev.moveto($game_player.x, $game_player.y)
      ev.direction = $game_player.direction
      data.invisible_after_transfer = true
    end
    record_position(ev)
  end

  # Saves the event's position into data.
  # @param ev [Game_FollowingPokemon]
  def record_position(ev)
    data.current_map_id = ev.map.map_id
    data.x              = ev.x
    data.y              = ev.y
    data.direction      = ev.direction
  end
end
