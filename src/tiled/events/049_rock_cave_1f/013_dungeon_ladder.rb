# Event 13 "Dungeon ladder" on Rock Cave 1F (map 49)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *comment(
    "Set which dungeon parameters are to be used for the ",
    "next dungeon map entered. These parameters are ",
    "defined in the PBS file dungeon_parameters.txt",
  ),
  *comment(
    "You can set the following:",
    "$PokemonGlobal.dungeon_area = :forest",
    "$PokemonGlobal.dungeon_version = 42",
  ),
  script("$PokemonGlobal.dungeon_area = :cave"),
  play_se(audio(name: "Door exit", volume: 80)),
  change_tone(tone(-255, -255, -255), frames: 6),
  wait(8),
  transfer_player(map: 51, x: 0, y: 0, direction: :right, fading: false),
  change_tone(tone(0, 0, 0), frames: 6),
]
