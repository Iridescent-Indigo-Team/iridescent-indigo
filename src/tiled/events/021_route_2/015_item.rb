# Event 15 "Item" on Route 2 (map 21)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *condition(
    script: "pbItemBall(:LEFTOVERS)",
    then: [
      control_self_switch("A", :ON),
    ],
  ),
]

page 1, []
