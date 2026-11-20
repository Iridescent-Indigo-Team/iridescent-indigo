# Event 6 "Town Map, size(2,1)" on Lerucean Town Poké Center (map 24)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *comment(
    "This event is size 2x1. It is 2 tiles wide and 1 tile tall. ",
    "An event's size can be set by adding \"size(x,y)\" in the ",
    "event's name, where x and y are numbers.",
  ),
  *comment(
    "The event's placed position determines the bottom ",
    "left tile occupied by the event in-game.",
  ),
  *comment(
    "There are a lot of reasons to change an event's size. ",
    "Here, it is covering the whole wall map with just one ",
    "event, rather than needing two events that do the ",
    "same thing.",
  ),
  script("pbShowMap"),
]
