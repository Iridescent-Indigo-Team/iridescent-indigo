# Event 7 "Trainer(1)" on Route 3 (map 31)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  script("pbTrainerIntro(:BEAUTY)"),
  script("pbNoticePlayer(get_self)"),
  text("\\rI've brought my own special backdrop!"),
  *script(
    <<~'CODE'
    setBattleRule(
      "backdrop", "champion1"
    )
    CODE
  ),
  *condition(
    script: "TrainerBattle.start(:BEAUTY, \"Bridget\")",
    then: [
      control_self_switch("A", :ON),
    ],
  ),
  script("pbTrainerEnd"),
]

page 1, [
  *text(
    "\\rIf exactly 2 trainers notice you at the same time, ",
    "they become a double battle.",
  ),
  *text(
    "\\rHere, though, 3 trainers noticed you at once, so I ",
    "battled you by myself. Then the 2 remaining trainers ",
    "noticing you at the same time became a double battle.",
  ),
  *text(
    "\\rI battled you first because my event's ID number (7) ",
    "comes before the Hiker's and Fisherman's event ID ",
    "numbers (8 and 9).",
  ),
]
