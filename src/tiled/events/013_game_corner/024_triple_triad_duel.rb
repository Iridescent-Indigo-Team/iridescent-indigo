# Event 24 "Triple Triad duel" on Game Corner (map 13)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  text("\\bI'm ready to duel with you."),
  *condition(
    script: "pbCanTriadDuel?",
    then: [
      *comment(
        "The two numbers are the min and max level of the ",
        "opponent respectively. Each number can be between ",
        "0 and 9 inclusive, and the max level must be higher ",
        "than or equal to the min level.",
      ),
      script("pbTriadDuel(\"Jack\", 0, 5)"),
    ],
    else: [
      *text(
        "\\bOh, you don't have enough cards to play. You need ",
        "at least 5.",
      ),
    ],
  ),
]
