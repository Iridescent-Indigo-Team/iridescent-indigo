# Event 16 "Voltorb Flip" on Game Corner (map 13)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *move_route(
    character(18),
    turn_down,
  ),
  wait_completion,
  *text(
    "\\bMr. Game: Show me how you play and make my ",
    "heart pound with excitement!",
  ),
  script("pbVoltorbFlip"),
]
