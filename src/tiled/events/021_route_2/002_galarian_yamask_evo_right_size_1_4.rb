# Event 2 "Galarian Yamask evo right size(1,4)" on Route 2 (map 21)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *condition(
    character: player,
    facing: :left,
    then: [
      script("pbEvolutionEvent(2)"),
    ],
  ),
]
