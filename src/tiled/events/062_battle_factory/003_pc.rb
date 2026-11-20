# Event 3 "PC" on Battle Factory (map 62)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *condition(
    character: player,
    facing: :up,
    then: [
      script("pbPokeCenterPC"),
    ],
  ),
]
