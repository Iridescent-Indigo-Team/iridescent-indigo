# Event 3 "Champion" on Pokémon League room 1 (map 37)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  script("pbTrainerIntro(:CHAMPION)"),
  *text(
    "\\bEverything in here uses a temporary switch to ",
    "decide what to do, rather than a Self Switch, ",
    "because it all needs to reset each time you enter.",
  ),
  *condition(
    script: "TrainerBattle.start(:CHAMPION, \"Blue\")",
    then: [
      script("setTempSwitchOn(\"A\")"),
      comment("Open door."),
      script("get_character(1).setTempSwitchOn(\"A\")"),
    ],
  ),
  script("pbTrainerEnd"),
]

page 1, [
  text("\\bYou beat me! Go on to the Hall of Fame."),
]
