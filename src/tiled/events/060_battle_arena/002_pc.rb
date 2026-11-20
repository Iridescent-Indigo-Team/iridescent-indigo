# Event 2 "PC" on Battle Arena (map 60)
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
