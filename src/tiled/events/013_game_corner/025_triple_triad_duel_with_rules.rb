# Event 25 "Triple Triad duel with rules" on Game Corner (map 13)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  text("\\rReady for a real rule duel?"),
  *condition(
    script: "pbCanTriadDuel?",
    then: [
      *comment(
        "This duel includes certain battle rules. See the wiki ",
        "for details of what rules can be applied.",
      ),
      *script(
        <<~'CODE'
        pbTriadDuel("Alice", 0, 5,
          ["countunplayed",
          "samewins",
          "elements",
          "direct"]
        )
        CODE
      ),
    ],
    else: [
      *text(
        "\\rOh, you don't have enough cards to play. You need ",
        "at least 5.",
      ),
    ],
  ),
]
