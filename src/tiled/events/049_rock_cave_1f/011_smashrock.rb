# Event 11 "SmashRock" on Rock Cave 1F (map 49)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *move_route(
    this,
    turn_down,
  ),
  *condition(
    script: "pbRockSmash",
    then: [
      script("pbSmashThisEvent"),
      script("pbRockSmashRandomEncounter"),
    ],
  ),
]
