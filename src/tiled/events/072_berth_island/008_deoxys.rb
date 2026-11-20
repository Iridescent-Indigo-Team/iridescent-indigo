# Event 8 "Deoxys" on Berth Island (map 72)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  script("Pokemon.play_cry(:DEOXYS)"),
  wait(15),
  control_switches(s(32), :ON),
  script("WildBattle.start(:DEOXYS, 30)"),
  control_switches(s(32), :OFF),
  control_self_switch("A", :ON),
]

page 1, []
