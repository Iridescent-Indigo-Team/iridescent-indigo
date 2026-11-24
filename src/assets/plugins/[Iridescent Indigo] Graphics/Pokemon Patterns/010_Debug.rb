#================================================================================================
# Pokémon Iridescent Indigo Graphics/Pokemon Patterns - 010_Debug.rb
#================================================================================================

#==================================================================
# module PatternDebug
#==================================================================
# @brief Text helpers for the "Set pattern" debug option.
module PatternDebug
  module_function

  # @brief Describes a Pokémon's pattern in one line, including whether it has sprites.
  # @param pkmn [Pokemon]
  # @return [String]
  def summary(pkmn)
    pattern = pkmn.pattern_simple
    return _INTL("Pattern: not rolled yet.") if pattern.nil?
    return _INTL("Pattern: none.") if pattern == PatternData::NONE
    if !PatternData.valid?(pkmn.species, pattern)
      return _INTL("Pattern: {1} (not in this line; normal sprites are shown).", pattern)
    end
    name = PatternData.name_for(pkmn.species, pattern)
    front = PatternSprites.resolve("Graphics/Pokemon/", "Front", pkmn.species, pkmn.form, pkmn.gender,
                                   pkmn.shiny?, pkmn.shadowPokemon?, pattern)
    return _INTL("Pattern: {1} ({2}).", name, pattern) if front
    return _INTL("Pattern: {1} ({2}), but it has no sprite here, so normal sprites are shown.", name, pattern)
  end
end

MenuHandlers.add(:pokemon_debug_menu, :set_pattern, {
  "name"   => _INTL("Set pattern"),
  "parent" => :cosmetic,
  "effect" => proc { |pkmn, pkmnid, heldpoke, settingUpBattle, screen|
    if !PatternData.has_patterns?(pkmn.species)
      screen.pbDisplay(_INTL("{1}'s evolution line has no patterns.", pkmn.speciesName))
      next false
    end
    cmd = 0
    loop do
      ids = PatternData.ids_for(pkmn.species)
      commands = ids.map do |id|
        mark = (pkmn.pattern_simple == id) ? "* " : ""
        next "#{mark}#{PatternData.name_for(pkmn.species, id)} (#{id})"
      end
      commands.push(_INTL("No pattern"), _INTL("Re-roll"), _INTL("Clear (roll when next needed)"))
      cmd = screen.pbShowCommands(PatternDebug.summary(pkmn), commands, cmd)
      break if cmd < 0
      if cmd < ids.length
        pkmn.pattern = ids[cmd]
      elsif cmd == ids.length
        pkmn.pattern = PatternData::NONE
      elsif cmd == ids.length + 1
        pkmn.pattern = PatternData.roll(pkmn.species)
      else
        pkmn.pattern = nil
      end
      $player.pokedex.register(pkmn) if !settingUpBattle && !pkmn.egg?
      screen.pbRefreshSingle(pkmnid)
    end
    next false
  }
})
