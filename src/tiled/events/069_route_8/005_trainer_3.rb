# Event 5 "Trainer(3)" on Route 8 (map 69)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  script("pbTrainerIntro(:SWIMMER2_F)"),
  script("pbNoticePlayer(get_self)"),
  *text(
    "\\rI'm a swimming trainer, just like any other",
    "trainer!",
  ),
  *condition(
    script: "TrainerBattle.start(:SWIMMER2_F, \"Ariel\")",
    then: [
      control_self_switch("A", :ON),
    ],
  ),
  script("pbTrainerEnd"),
]

page 1, [
  *text(
    "\\rJust make sure swimming trainers don't",
    "try to swim over land to get to the player when they",
    "spot them.",
  ),
]
