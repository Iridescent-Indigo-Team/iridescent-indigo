# Event 5 "Cashier top" on Cedolan Dept. 2F (map 15)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *script(
    <<~'CODE'
    pbPokemonMart([
      :POTION, :SUPERPOTION,
      :HYPERPOTION, :MAXPOTION,
      :FULLRESTORE, :REVIVE,
      :ANTIDOTE, :PARALYZEHEAL,
      :BURNHEAL, :ICEHEAL,
      :AWAKENING, :FULLHEAL
    ])
    CODE
  ),
]
