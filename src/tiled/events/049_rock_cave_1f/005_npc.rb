# Event 5 "NPC" on Rock Cave 1F (map 49)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  text("\\bCan you push that boulder onto the switch?"),
  *condition(
    self_switch: "A",
    value: :ON,
    then: [
      text("\\bOh! The boulder has been moved onto the switch!"),
      text("\\bWell done!"),
    ],
    else: [
      text("\\bOh. The boulder is not on the switch."),
    ],
  ),
]
