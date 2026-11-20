# Event 8 "Trainer(1)" on Route 3 (map 31)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  script("pbTrainerIntro(:HIKER)"),
  script("pbNoticePlayer(get_self)"),
  text("\\bThis battle will go without a hitch!"),
  *condition(
    script: "TrainerBattle.start(:HIKER, \"Ford\")",
    then: [
      control_self_switch("A", :ON),
    ],
  ),
  script("pbTrainerEnd"),
]

page 1, [
  text("\\bHow did you manage to face all three of us?"),
]
