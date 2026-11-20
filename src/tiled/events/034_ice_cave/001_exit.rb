# Event 1 "Exit" on Ice Cave (map 34)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  change_tone(tone(-255, -255, -255), frames: 6),
  wait(8),
  script("pbCaveExit"),
  transfer_player(map: 31, x: 55, y: 8, direction: :retain, fading: false),
  change_tone(tone(0, 0, 0), frames: 6),
]
