# Event 1 "Counter(6)" on Route 6 Cycling Road gate (map 74)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *comment(
    "This event can notice the player at a distance even ",
    "though an impassable tile (the desk) is in the way. ",
    "This is because this event's name contains the text ",
    "\"Counter(X)\", where \"X\" is the number of tiles in front ",
    "of itself that it can see.",
  ),
  *condition(
    script: "$bag.has?(:BICYCLE)",
    then: [
      script("setTempSwitchOn(\"A\")"),
    ],
    else: [
      script("pbExclaim(get_self)"),
      *text(
        "\\bSorry, you can't enter Cycle Road without a ",
        "Bicycle.",
      ),
      *move_route(
        player,
        turn_right,
        move_right,
      ),
    ],
  ),
]

page 1, [
  text("\\bCycling Road is a great ride."),
]
