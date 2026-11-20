# Event 4 "Exit north right" on Route 4 Cycling Road gate (map 46)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  play_se(audio(name: "Door exit", volume: 80)),
  change_tone(tone(-255, -255, -255), frames: 6),
  wait(8),
  transfer_player(map: 39, x: 31, y: 14, direction: :retain, fading: false),
  change_tone(tone(0, 0, 0), frames: 6),
]
