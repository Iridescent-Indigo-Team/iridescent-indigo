# Event 9 "Sign" on Rock Cave 1F (map 49)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *text(
    "The positions of the boulders are checked by a ",
    "Parallel Process event.",
  ),
  *text(
    "The hole event must have its \"Through\" option set, to ",
    "allow boulder events to be pushed onto it.",
  ),
]
