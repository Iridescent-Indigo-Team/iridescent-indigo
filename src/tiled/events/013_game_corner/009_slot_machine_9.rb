# Event 9 "Slot Machine 9" on Game Corner (map 13)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *condition(
    character: player,
    facing: :right,
    then: [
      script("pbSlotMachine"),
    ],
  ),
]
