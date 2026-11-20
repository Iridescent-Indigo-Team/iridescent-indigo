# Event 5 "Shadow trainer - basic" on Route 7 (map 47)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  script("pbTrainerIntro(:TEAMROCKET_M)"),
  text("\\bI'm a basic trainer with a Shadow Pokémon."),
  *condition(
    script: "TrainerBattle.start(:TEAMROCKET_M, \"Grunt\", 1)",
    then: [
      control_self_switch("A", :ON),
    ],
  ),
  script("pbTrainerEnd"),
]

page 1, [
  *text(
    "\\bDid you manage to snag my Shadow Pokémon?  ",
    "Because you can't battle me again for another ",
    "chance.",
  ),
]
