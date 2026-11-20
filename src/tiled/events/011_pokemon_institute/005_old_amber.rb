# Event 5 "Old Amber" on Pokémon Institute (map 11)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *condition(
    script: "pbItemBall(:OLDAMBER)",
    then: [
      control_self_switch("A", :ON),
    ],
  ),
]

page 1, []
