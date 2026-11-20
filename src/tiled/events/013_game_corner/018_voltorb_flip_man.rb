# Event 18 "Voltorb Flip man" on Game Corner (map 13)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *condition(
    self_switch: "A",
    value: :OFF,
    then: [
      text("\\bMy name is Mr. Game!"),
      *text(
        "\\bMy heart pounds with excitement when people ",
        "enjoy my Coin game!",
      ),
      text("\\bIn fact, that's what I live for!\\nGo ahead and play it!"),
      text("\\bMake my heart pound with excitement!"),
      control_self_switch("A", :ON),
    ],
    else: [
      text("\\bGo ahead and play my Coin game!"),
      text("\\bMake my heart pound with excitement!"),
    ],
  ),
]
