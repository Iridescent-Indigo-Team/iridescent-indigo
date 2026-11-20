# Event 6 "Hole" on Ice Cave (map 34)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  wait(4),
  play_se(audio(name: "Player fall", volume: 80)),
  change_transparent_flag(:transparent),
  wait(4),
  change_tone(tone(-255, -255, -255), frames: 6),
  wait(8),
  transfer_player(map: 34, x: 16, y: 30, direction: :retain, fading: false),
  change_transparent_flag(:normal),
  change_tone(tone(0, 0, 0), frames: 6),
]
