# Event 10 "Time-dependent NPC" on Route 7 (map 47)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *text(
    "\\bHello. This is what I say if you talk to me during the ",
    "day.",
  ),
]

page 1, [
  text("\\bHalt! Who goes there?"),
  text("\\bThis is what I say if you talk to me at night."),
  text("\\bI could battle you... but I won't."),
]
