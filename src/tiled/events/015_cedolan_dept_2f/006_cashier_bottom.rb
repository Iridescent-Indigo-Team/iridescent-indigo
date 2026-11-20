# Event 6 "Cashier bottom" on Cedolan Dept. 2F (map 15)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *script(
    <<~'CODE'
    pbPokemonMart([
      :POKEBALL, :GREATBALL, :ULTRABALL,
      :ESCAPEROPE,
      :REPEL, :SUPERREPEL, :MAXREPEL,
      :GRASSMAIL, :FLAMEMAIL,
      :BUBBLEMAIL, :SPACEMAIL
    ])
    CODE
  ),
]
