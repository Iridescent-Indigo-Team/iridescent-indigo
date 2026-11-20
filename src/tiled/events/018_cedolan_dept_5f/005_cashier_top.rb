# Event 5 "Cashier top" on Cedolan Dept. 5F (map 18)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *script(
    <<~'CODE'
    pbPokemonMart([
      :HPUP,
      :PROTEIN,
      :IRON,
      :CALCIUM,
      :ZINC,
      :CARBOS
    ])
    CODE
  ),
]
