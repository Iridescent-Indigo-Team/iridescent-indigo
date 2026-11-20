# Event 10 "Trainer(2)" on Route 3 (map 31)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  script("pbTrainerIntro(:LASS)"),
  script("pbNoticePlayer(get_self)"),
  text("\\rGet ready for a double battle!"),
  script("setBattleRule(\"double\")"),
  *condition(
    script: "TrainerBattle.start(:LASS, \"Crissy\")",
    then: [
      control_self_switch("A", :ON),
    ],
  ),
  script("pbTrainerEnd"),
]

page 1, [
  *text(
    "\\rMake sure all double battle opponents have at least ",
    "2 Pokémon!",
  ),
]
