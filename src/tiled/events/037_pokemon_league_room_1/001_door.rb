# Event 1 "Door" on Pokémon League room 1 (map 37)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, []

page 1, [
  play_se(audio(name: "Door exit", volume: 80)),
  change_tone(tone(-255, -255, -255), frames: 6),
  wait(8),
  transfer_player(map: 38, x: 5, y: 12, direction: :up, fading: false),
  change_tone(tone(0, 0, 0), frames: 6),
  control_self_switch("A", :OFF),
]
