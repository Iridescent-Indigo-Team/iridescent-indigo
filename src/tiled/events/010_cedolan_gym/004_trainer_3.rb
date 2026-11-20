# Event 4 "Trainer(3)" on Cedolan Gym (map 10)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  script("pbTrainerIntro(:CAMPER)"),
  script("pbNoticePlayer(get_self)"),
  text("\\bBattle me now!"),
  *condition(
    script: "TrainerBattle.start(:CAMPER, \"Liam\")",
    then: [
      control_self_switch("A", :ON),
    ],
  ),
  script("pbTrainerEnd"),
]

page 1, [
  *text(
    "\\bYou're pretty hot. But not as hot as",
    "Brock!",
  ),
]

page 2, [
  *text(
    "\\bYou're pretty hot. But not as hot as",
    "Brock!",
  ),
]
