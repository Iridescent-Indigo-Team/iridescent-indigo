# Event 2 "Exit right" on Rock Cave 1F (map 49)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  play_se(audio(name: "Door exit", volume: 80)),
  change_tone(tone(-255, -255, -255), frames: 6),
  wait(8),
  script("pbCaveExit"),
  transfer_player(map: 47, x: 56, y: 16, direction: :retain, fading: false),
  change_tone(tone(0, 0, 0), frames: 6),
]
