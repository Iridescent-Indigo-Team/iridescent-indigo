# Event 2 "Daisy" on Daisy's house (map 8)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  text("\\rDaisy: Hi, \\PN!"),
  *text(
    "\\rDaisy: Would you like me to groom one of your ",
    "Pokémon?",
  ),
  *show_choices(
    choices: ["Yes", "No"],
    cancellation: 2,
    choice1: [
      text("\\rDaisy: Which Pokémon do you want me to groom?"),
      script("pbChooseNonEggPokemon(1, 2)"),
      *condition(
        variable: v(1),
        operation: "<",
        constant: 0,
        then: [
          text("\\rDaisy: Oh, okay then."),
          exit_event_processing,
        ],
      ),
      *script(
        <<~'CODE'
        pkmn = pbGetPokemon(1)
        pkmn.changeHappiness("groom")
        pkmn.beauty += 40
        CODE
      ),
      *text(
        "\\rDaisy: There! \\v[2] looks a lot happier and prettier ",
        "now!",
      ),
    ],
    choice2: [
      text("\\rDaisy: Oh, okay then."),
    ],
  ),
]
