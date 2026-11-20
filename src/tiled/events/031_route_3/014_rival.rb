# Event 14 "Rival" on Route 3 (map 31)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *comment(
    "This event should be somewhere where the player ",
    "can't possibly see it.",
    "It is moved from here to where it is needed when its ",
    "appearance is triggered.",
  ),
  *comment(
    "Note that this event does nothing except look like an ",
    "NPC (the Rival). The actual battle and movements ",
    "are done by the controlling event at the entrance of ",
    "this short path.",
  ),
]

page 1, []
