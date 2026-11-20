# Event 9 "Trainer(1)" on Route 3 (map 31)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  script("pbTrainerIntro(:FISHERMAN)"),
  script("pbNoticePlayer(get_self)"),
  text("\\bI'll get my tackle out for you!"),
  *condition(
    script: "TrainerBattle.start(:FISHERMAN, \"Andrew\")",
    then: [
      control_self_switch("A", :ON),
    ],
  ),
  script("pbTrainerEnd"),
]

page 1, [
  *text(
    "\\bI don't understand why my Magikarp couldn't beat ",
    "you.",
  ),
]
