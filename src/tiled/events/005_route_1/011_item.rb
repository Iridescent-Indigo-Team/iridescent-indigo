# Event 11 "Item" on Route 1 (map 5)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *condition(
    script: "pbItemBall(:GREATBALL)",
    then: [
      control_self_switch("A", :ON),
    ],
  ),
]

page 1, []
