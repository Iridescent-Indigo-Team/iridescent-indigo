# Event 18 "HiddenItem" on Route 2 (map 21)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *condition(
    script: "pbItemBall(:POTION)",
    then: [
      control_self_switch("A", :ON),
    ],
  ),
]

page 1, []
