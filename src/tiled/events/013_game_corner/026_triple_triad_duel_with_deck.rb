# Event 26 "Triple Triad duel with deck" on Game Corner (map 13)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  text("\\bI built my deck specially for this!"),
  *condition(
    script: "pbCanTriadDuel?",
    then: [
      *comment(
        "This duel has no special rules, and has a predefined ",
        "opponent's deck. The level numbers are unused, but ",
        "still need to be defined (each being 0-9).",
      ),
      *script(
        <<~'CODE'
        pbTriadDuel("Tim", 0, 5, nil,
          [:BULBASAUR, :CHARMANDER,
           :SQUIRTLE, :PIKACHU, :CLEFAIRY]
        )
        CODE
      ),
    ],
    else: [
      *text(
        "\\bOh, you don't have enough cards to play. You need ",
        "at least 5.",
      ),
    ],
  ),
]
