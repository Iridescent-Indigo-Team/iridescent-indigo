# Event 10 "Wall sign left" on Pokémon Lab (map 4)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *text(
    "The event next to the Professor contains the autorun ",
    "commands.",
  ),
  *text(
    "There are two times it does something: when the ",
    "player first enters the map, and when the player has ",
    "chosen a starter.",
  ),
  *text(
    "The second time is on a higher page number. Page ",
    "numbers go in order of first to last cutscene, ",
    "including pages for pauses between them if relevant.",
  ),
]
