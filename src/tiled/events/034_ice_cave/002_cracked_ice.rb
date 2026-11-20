# Event 2 "Cracked ice" on Ice Cave (map 34)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  play_se(audio(name: "Battle catch click")),
  control_self_switch("A", :ON),
]

page 1, [
  *move_route(
    this,
    remove_graphic,
  ),
  play_se(audio(name: "Battle catch click")),
  wait(4),
  play_se(audio(name: "Battle throw")),
  change_transparent_flag(:transparent),
  wait(4),
  change_tone(tone(-255, -255, -255), frames: 6),
  wait(8),
  transfer_player(map: 34, x: 20, y: 32, direction: :retain, fading: false),
  change_transparent_flag(:normal),
  change_tone(tone(0, 0, 0), frames: 6),
  control_self_switch("A", :OFF),
]
