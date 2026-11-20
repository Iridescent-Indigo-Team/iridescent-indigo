# Event 5 "Cashier" on Cedolan Dept. 4F (map 17)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *script(
    <<~'CODE'
    pbPokemonMart([
      :POKEDOLL,
      :AIRMAIL, :TUNNELMAIL, :BLOOMMAIL,
      :FIRESTONE, :THUNDERSTONE,
      :WATERSTONE, :LEAFSTONE
    ])
    CODE
  ),
]
