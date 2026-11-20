# Event 5 "Singles results" on Battle Tower (map 55)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  text("Check results for which challenge?"),
  *show_choices(
    choices: ["Level 50", "Open Level", "Cancel"],
    cancellation: 3,
    choice1: [
      *script(
        <<~'CODE'
        pbSet(1,
          pbBattleChallenge.getPreviousWins(
          "towersingle")
        )
        pbSet(2,
          pbBattleChallenge.getMaxWins(
          "towersingle")
        )
        CODE
      ),
      text("\\PN's Battle Tower Level 50 Single Battle results:"),
      text("Last win streak: \\v[1]\\nRecord win streak: \\v[2]"),
    ],
    choice2: [
      *script(
        <<~'CODE'
        pbSet(1,
          pbBattleChallenge.getPreviousWins(
          "towersingleopen")
        )
        pbSet(2,
          pbBattleChallenge.getMaxWins(
          "towersingleopen")
        )
        CODE
      ),
      text("\\PN's Battle Tower Open Level Single Battle results:"),
      text("Last win streak: \\v[1]\\nRecord win streak: \\v[2]"),
    ],
  ),
]
