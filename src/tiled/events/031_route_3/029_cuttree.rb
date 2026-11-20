# Event 29 "CutTree" on Route 3 (map 31)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *move_route(
    this,
    turn_down,
  ),
  *condition(
    script: "pbCut",
    then: [
      script("pbSmashThisEvent"),
    ],
  ),
]
