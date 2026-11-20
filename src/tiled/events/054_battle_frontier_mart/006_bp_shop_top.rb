# Event 6 "BP shop top" on Battle Frontier Mart (map 54)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *script(
    <<~'CODE'
    pbBattlePointShop([
      :SCOPELENS, :WIDELENS, :ZOOMLENS,
      :WISEGLASSES, :MUSCLEBAND,
      :BINDINGBAND,
      :RAZORCLAW, :RAZORFANG,
      :AIRBALLOON, :IRONBALL, :TOXICORB,
      :FLAMEORB, :LIFEORB,
      :WHITEHERB, :POWERHERB,
      :ABSORBBULB, :CELLBATTERY,
      :REDCARD, :EJECTBUTTON, :RARECANDY
    ])
    CODE
  ),
]
