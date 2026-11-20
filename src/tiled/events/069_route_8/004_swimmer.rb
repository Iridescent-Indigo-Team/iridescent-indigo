# Event 4 "Swimmer" on Route 8 (map 69)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  text("\\bI'm just swimming around in this 5x5 area."),
  *text(
    "\\bMy custom autonomous movement calls a method ",
    "which makes me move randomly, but not further than ",
    "2 tiles horizontally or vertically from my initial position.",
  ),
  *text(
    "\\bOther scripts that could be called here are ",
    "move_random_UD(range) for up/down only and ",
    "move_random_LR(range) for left/right only.",
  ),
]
move_route 0, route(
  route_script("move_random_range(2,2)"),
  skippable: true,
)
