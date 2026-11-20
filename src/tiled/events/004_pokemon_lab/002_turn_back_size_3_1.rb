# Event 2 "Turn back, size(3,1)" on Pokémon Lab (map 4)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *comment(
    "This event is size 3x1. It is 3 tiles wide and 1 tile tall. ",
    "An event's size can be set by adding \"size(x,y)\" in the ",
    "event's name, where x and y are numbers.",
  ),
  *comment(
    "The event's placed position determines the bottom ",
    "left tile occupied by the event in-game.",
  ),
  *comment(
    "There are a lot of reasons to change an event's size. ",
    "Here, it is covering the whole distance between the ",
    "bookshelves with just one event, rather than needing ",
    "three events that do the same thing.",
  ),
]

page 1, [
  text("\\bOak: Wait, don't leave yet!"),
  *move_route(
    player,
    turn_180,
    move_forward,
  ),
]
