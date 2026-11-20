# Event 4 "Hole" on Rock Cave 1F (map 49)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  wait(4),
  play_se(audio(name: "Player fall", volume: 80)),
  change_transparent_flag(:transparent),
  wait(4),
  change_tone(tone(-255, -255, -255), frames: 6),
  wait(8),
  transfer_player(map: 50, x: 12, y: 7, direction: :retain, fading: false),
  change_transparent_flag(:normal),
  change_tone(tone(0, 0, 0), frames: 6),
]
