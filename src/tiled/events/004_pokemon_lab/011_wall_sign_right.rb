# Event 11 "Wall sign right" on Pokémon Lab (map 4)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *text(
    "Game Variable 7 should store 1 if the player ",
    "chose the Grass starter, 2 if they chose the Fire ",
    "starter, and 3 if they chose the Water starter.",
  ),
  *text(
    "This information can be used later in the game, e.g. ",
    "to determine which Pokémon the rival uses, and to ",
    "detect when the player has chosen a starter at all.",
  ),
]
