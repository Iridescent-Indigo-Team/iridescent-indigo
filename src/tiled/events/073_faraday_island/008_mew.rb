# Event 8 "Mew" on Faraday Island (map 73)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *comment(
    "Mew reappears after each time the Elite Four are ",
    "defeated. The command that does this is in the event ",
    "in the Hall of Fame map.",
    "Mew will not reappear if it has been caught, though. ",
    "This is why this event sets Self Switch B if it is caught, ",
    "to avoid it reappearing.",
  ),
  script("Pokemon.play_cry(:MEW)"),
  wait(15),
  control_switches(s(31), :ON),
  control_switches(s(32), :ON),
  script("WildBattle.start(:MEW, 30)"),
  control_switches(s(31), :OFF),
  control_switches(s(32), :OFF),
  *comment(
    "A battle's outcome is stored in Game Variable 1 by ",
    "default. You can change this by putting the script ",
    "\"setBattleRule(\"outcome\", 42)\" before the battle, ",
    "where 42 is the Game Variable number you want.",
  ),
  *condition(
    variable: v(1),
    operation: "==",
    constant: 4,
    then: [
      comment("Caught."),
      control_self_switch("B", :ON),
    ],
    else: [
      control_self_switch("A", :ON),
    ],
  ),
]

page 1, [
  *condition(
    switch: s(56),
    value: :ON,
    then: [
      control_switches(s(56), :OFF),
      control_self_switch("A", :OFF),
    ],
  ),
]

page 2, []
