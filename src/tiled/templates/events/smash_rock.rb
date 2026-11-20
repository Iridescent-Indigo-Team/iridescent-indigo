# Template: rock that can be smashed (may start a wild encounter).

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
