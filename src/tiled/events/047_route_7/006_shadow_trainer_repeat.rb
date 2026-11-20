# Event 6 "Shadow trainer - repeat" on Route 7 (map 47)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  script("pbTrainerIntro(:TEAMROCKET_F)"),
  *text(
    "\\rYou can battle me repeatedly, and have unlimited ",
    "attempts to snag my Shadow Pokémon.",
  ),
  *condition(
    script: "TrainerBattle.start(:TEAMROCKET_F, \"Grunt\", 1)",
    then: condition(
      script: "$player.pokedex.owned_shadow_pokemon?(:ELECTABUZZ)",
      then: [
        control_self_switch("A", :ON),
      ],
    ),
  ),
  script("pbTrainerEnd"),
]

page 1, [
  *text(
    "\\rYou've managed to snag my Shadow Electabuzz.  ",
    "I'm not going to do anything now.",
  ),
]
