# Event 10 "Slot Machine 10" on Game Corner (map 13)
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
