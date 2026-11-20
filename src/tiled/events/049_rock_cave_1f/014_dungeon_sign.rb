# Event 14 "Dungeon sign" on Rock Cave 1F (map 49)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  text("This ladder leads to a random dungeon."),
  *text(
    "The levels of Pokémon within are based on the levels ",
    "of Pokémon in the player's party.",
  ),
  *text(
    "This is because the dungeon map's metadata gives it ",
    "the \"ScaleWildEncounterLevels\" flag.",
  ),
]
