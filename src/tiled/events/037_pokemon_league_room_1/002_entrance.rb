# Event 2 "Entrance" on Pokémon League room 1 (map 37)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *move_route(
    player,
    route_wait(8),
    through_on,
    move_up,
    move_up,
    move_up,
    move_up,
    move_up,
    through_off,
    skippable: true,
  ),
  wait_completion,
  play_se(audio(name: "Door enter")),
  script("setTempSwitchOn(\"A\")"),
]

page 1, []
