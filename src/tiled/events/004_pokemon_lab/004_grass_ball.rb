# Event 4 "Grass ball" on Pokémon Lab (map 4)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *text(
    "This ball contains a Pokémon caught by the ",
    "Professor.",
  ),
]

page 1, [
  text("\\bOak: So, you want Bulbasaur, the grass Pokémon?"),
  *show_choices(
    choices: ["Yes", "No"],
    cancellation: 2,
    choice1: [
      script("pbAddPokemon(:BULBASAUR, 5)"),
      control_switches(s(3), :OFF),
      control_variables(v(7), constant: 1),
      control_self_switch("A", :ON),
    ],
    choice2: [
      text("\\bOak: Choose carefully!"),
    ],
  ),
]

page 2, []
