# Event 27 "Triple Triad duel with prize" on Game Corner (map 13)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  text("\\rIf you win, I'll give you an Arceus card!"),
  *condition(
    script: "pbCanTriadDuel?",
    then: [
      *comment(
        "This duel has a prize card defined, which the player ",
        "gets if they win (ignoring any rule which affects ",
        "prizes).  If the player draws or loses, however, the ",
        "rules apply normally.",
      ),
      *script(
        <<~'CODE'
        pbTriadDuel("Sophie", 0, 5, nil, nil,
          :ARCEUS
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
