# Event 3 "Pokémon ball - Basic" on Pokémon Fan Club (map 26)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *comment(
    "This is a straightforward example of giving a ",
    "Pokémon to the player. Its OT will be the player.",
  ),
  *condition(
    script: "pbAddPokemon(:FARFETCHD, 20)",
    then: [
      control_self_switch("A", :ON),
    ],
  ),
]

page 1, []
