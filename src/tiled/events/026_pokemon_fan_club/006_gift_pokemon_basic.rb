# Event 6 "Gift Pokémon - Basic" on Pokémon Fan Club (map 26)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *text(
    "\\bMy Shuckie is a great Pokémon, but I can't train",
    "it anymore.",
  ),
  *text(
    "\\bWould you take Shuckie and raise it like it ",
    "deserves?",
  ),
  *show_choices(
    choices: ["Yes", "No"],
    cancellation: 2,
    choice1: [
      *comment(
        "pbAddForeignPokemon can only add a Pokémon to ",
        "the player's party, so a space is required.",
      ),
      *condition(
        script: "pbAddForeignPokemon(:SHUCKLE, 20, _I(\"Kirk\"), _I(\"Shuckie\"))",
        then: [
          text("\\bTake good care of Shuckie!"),
          control_self_switch("A", :ON),
        ],
        else: [
          text("\\bOh, you don't have any space for it."),
        ],
      ),
    ],
    choice2: [
      text("\\bOh, that's a shame."),
    ],
  ),
]

page 1, [
  text("\\bAre you raising my Shuckie well?"),
]
