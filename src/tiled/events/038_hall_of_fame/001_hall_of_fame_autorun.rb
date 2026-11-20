# Event 1 "Hall of Fame autorun" on Hall of Fame (map 38)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *comment(
    "Set various switches and counters.",
    "Also reset stationary Pokémon that reappear each ",
    "time the player defeats the Elite Four.",
  ),
  control_switches(s(12), :ON),
  control_variables(v(13), "+=", constant: 1),
  script("$stats.hall_of_fame_entry_count += 1"),
  control_switches(s(56), :ON),
  *comment(
    "Heal the player's party, and give the party Pokémon ",
    "ribbons for defeating the Elite Four.",
  ),
  recover_all(0),
  *script(
    <<~'CODE'
    $player.pokemon_party.each do |pkmn|
      pkmn.giveRibbon(:CHAMPION)
    end
    CODE
  ),
  *comment(
    "Make the player walk up to the recording station, ",
    "and fade to black.",
  ),
  wait(8),
  *move_route(
    player,
    turn_up,
    move_up,
    move_up,
    move_up,
    move_up,
    move_up,
    move_up,
    move_up,
    skippable: true,
  ),
  wait_completion,
  wait(8),
  change_tone(tone(-255, -255, -255), frames: 6),
  wait(8),
  comment("Record an entry in the Hall of Fame."),
  script("$stats.set_time_to_hall_of_fame"),
  script("pbHallOfFameEntry"),
  comment("Play the credits."),
  script("$scene = Scene_Credits.new"),
  wait(8),
  comment("Return the player to the entrance of the League."),
  transfer_player(map: 36, x: 13, y: 12, direction: :down, fading: false),
  change_tone(tone(0, 0, 0), frames: 6),
]
