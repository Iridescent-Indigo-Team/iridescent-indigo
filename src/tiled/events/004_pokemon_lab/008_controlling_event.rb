# Event 8 "Controlling event" on Pokémon Lab (map 4)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *move_route(
    player,
    turn_up,
    move_forward,
    move_forward,
    move_forward,
    move_forward,
    move_forward,
    move_forward,
    move_forward,
    skippable: true,
  ),
  wait_completion,
  text("\\bOak: Here, take one of these rare Pokémon."),
  control_switches(s(3), :ON),
]

page 1, []

page 2, [
  text("\\bOak: Ah, you made your choice!"),
  *condition(
    variable: v(7),
    operation: "==",
    constant: 1,
    then: [
      text("\\bOak: Bulbasaur, an excellent choice!"),
    ],
    else: condition(
      variable: v(7),
      operation: "==",
      constant: 2,
      then: [
        text("\\bOak: Charmander, an excellent choice!"),
      ],
      else: [
        text("\\bOak: Squirtle, an excellent choice!"),
      ],
    ),
  ),
  *text(
    "\\bOak: If I had a grandson, he would probably want ",
    "his own Pokémon around now...",
  ),
  control_self_switch("A", :ON),
]

page 3, []
