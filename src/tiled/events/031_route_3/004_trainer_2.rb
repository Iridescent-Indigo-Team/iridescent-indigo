# Event 4 "Trainer(2)" on Route 3 (map 31)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  script("pbTrainerIntro(:YOUNGSTER)"),
  script("pbNoticePlayer(get_self)"),
  text("\\bHi! I like shorts! They're comfy and easy to wear!"),
  *condition(
    script: "TrainerBattle.start(:YOUNGSTER, \"Ben\")",
    then: [
      control_self_switch("A", :ON),
    ],
  ),
  script("pbTrainerEnd"),
]

page 1, [
  text("\\bYou can't get a trainer event simpler than me!"),
]
