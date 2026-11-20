# Event 5 "BP shop bottom" on Battle Frontier Mart (map 54)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *script(
    <<~'CODE'
    pbBattlePointShop([
      :PROTEIN, :CALCIUM, :IRON,
      :ZINC, :CARBOS, :HPUP,
      :POWERBRACER, :POWERBELT,
      :POWERLENS, :POWERBAND,
      :POWERANKLET, :POWERWEIGHT,
      :CHOICEBAND, :CHOICESPECS,
      :CHOICESCARF,
      :FOCUSBAND, :FOCUSSASH
    ])
    CODE
  ),
]
