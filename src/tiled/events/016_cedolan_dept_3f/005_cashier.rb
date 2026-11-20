# Event 5 "Cashier" on Cedolan Dept. 3F (map 16)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *script(
    <<~'CODE'
    pbPokemonMart([
      :TM21, :TM27,
      :TM87, :TM78,
      :TM12, :TM41,
      :TM20, :TM28,
      :TM76, :TM55,
      :TM72, :TM79
    ])
    CODE
  ),
]
