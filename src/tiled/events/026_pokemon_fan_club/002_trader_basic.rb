# Event 2 "Trader - Basic" on Pokémon Fan Club (map 26)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  text("\\bI'm looking for a Rattata."),
  text("\\bWant to trade it for my Haunter?"),
  *show_choices(
    choices: ["Yes", "No"],
    cancellation: 2,
    choice1: [
      *comment(
        "The chosen Pokémon's party index goes in Game ",
        "Variable 1. A value of -1 means no Pokémon was ",
        "chosen.",
        "The chosen Pokémon's name goes in Game Variable 2.",
      ),
      *script(
        <<~'CODE'
        pbChoosePokemonForTrade(1, 2,
          :RATTATA
        )
        CODE
      ),
      *condition(
        variable: v(1),
        operation: "==",
        constant: -1,
        then: [
          text("\\bYou don't want to trade?  Aww..."),
        ],
        else: [
          text("\\bOK, let's get started."),
          *script(
            <<~'CODE'
            pbStartTrade(pbGet(1),
              :HAUNTER, _I("HaHa"), _I("Andy")
            )
            CODE
          ),
          text("\\PN traded Rattata for Haunter!"),
          text("\\bThanks!"),
          control_self_switch("A", :ON),
        ],
      ),
    ],
    choice2: [
      text("\\bYou don't want to trade? Aww..."),
    ],
  ),
]

page 1, [
  text("\\bThanks for trading with me!"),
]
