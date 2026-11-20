# Event 5 "Single results" on Battle Palace (map 58)
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
          "palacesingle")
        )
        pbSet(2,
          pbBattleChallenge.getMaxWins(
          "palacesingle")
        )
        CODE
      ),
      text("\\PN's Battle Palace Level 50 Single Battle results:"),
      text("Last win streak: \\v[1]\\nRecord win streak: \\v[2]"),
    ],
    choice2: [
      *script(
        <<~'CODE'
        pbSet(1,
          pbBattleChallenge.getPreviousWins(
          "palacesingleopen")
        )
        pbSet(2,
          pbBattleChallenge.getMaxWins(
          "palacesingleopen")
        )
        CODE
      ),
      text("\\PN's Battle Palace Open Level Single Battle results:"),
      text("Last win streak: \\v[1]\\nRecord win streak: \\v[2]"),
    ],
  ),
]
