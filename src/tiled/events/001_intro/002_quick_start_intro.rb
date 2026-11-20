# Event 2 "Quick start intro" on Intro (map 1)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *comment(
    "This is the Debug intro, used to quickly start a game. ",
    "The player's name and trainer type are chosen ",
    "automatically.",
  ),
  script("pbChangePlayer(1)"),
  script("pbTrainerName(\"Red\")"),
  control_self_switch("A", :ON),
  *script(
    <<~'CODE'
    pbToneChangeAll(
      Tone.new(-255, -255, -255, 0),
      0
    )
    CODE
  ),
  transfer_player(map: 3, x: 25, y: 6, direction: :down, fading: false),
  *script(
    <<~'CODE'
    pbToneChangeAll(
      Tone.new(0, 0, 0, 0),
      10
    )
    CODE
  ),
  wait(10),
]

page 1, []
