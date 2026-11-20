# Event 11 "Double trainer F" on Route 3 (map 31)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *condition(
    script: "!pbCanDoubleBattle?",
    then: [
      *text(
        "\\rYou'll need at least two Pokémon or a partner if you ",
        "want to battle us.",
      ),
      exit_event_processing,
    ],
  ),
  script("pbTrainerIntro(:COOLCOUPLE)"),
  text("\\rAh, looks like a challenging trainer. Ready, Bob?"),
  script("setBattleRule(\"double\")"),
  *condition(
    script: "TrainerBattle.start(:COOLCOUPLE, \"Alice & Bob\")",
    then: [
      control_self_switch("A", :ON),
      comment("Set the partner event's Self Switch \"A\" on."),
      script("pbSetSelfSwitch(12, \"A\", true)"),
    ],
  ),
  script("pbTrainerEnd"),
]

page 1, [
  *text(
    "\\rOur events weren't created by comments, ",
    "because we need to check how many Pokémon you ",
    "had.",
  ),
]
