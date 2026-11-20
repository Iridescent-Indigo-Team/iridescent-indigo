# Event 3 "BerryPlant" on Route 1 (map 5)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  script("pbPickBerry(:ORANBERRY, 2)"),
]

page 1, [
  script("pbBerryPlant"),
]
