# Event 4 "Results" on Battle Arena (map 60)
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
          "arena")
        )
        pbSet(2,
          pbBattleChallenge.getMaxWins(
          "arena")
        )
        CODE
      ),
      text("\\PN's Battle Arena Level 50 results:"),
      text("Last win streak: \\v[1]\\nRecord win streak: \\v[2]"),
    ],
    choice2: [
      *script(
        <<~'CODE'
        pbSet(1,
          pbBattleChallenge.getPreviousWins(
          "arenaopen")
        )
        pbSet(2,
          pbBattleChallenge.getMaxWins(
          "arenaopen")
        )
        CODE
      ),
      text("\\PN's Battle Arena Open Level results:"),
      text("Last win streak: \\v[1]\\nRecord win streak: \\v[2]"),
    ],
  ),
]
