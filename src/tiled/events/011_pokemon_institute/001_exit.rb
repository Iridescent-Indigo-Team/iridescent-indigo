# Event 1 "Exit" on Pokémon Institute (map 11)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *comment(
    "This command makes the fossil reviver finish reviving ",
    "a Pokémon.",
  ),
  control_switches(s(13), :OFF),
  play_se(audio(name: "Door exit", volume: 80)),
  change_tone(tone(-255, -255, -255), frames: 6),
  wait(8),
  transfer_player(map: 7, x: 35, y: 28, direction: :retain, fading: false),
  change_tone(tone(0, 0, 0), frames: 6),
]
