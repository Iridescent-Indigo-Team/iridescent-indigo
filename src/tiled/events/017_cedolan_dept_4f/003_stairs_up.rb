# Event 3 "Stairs up" on Cedolan Dept. 4F (map 17)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *move_route(
    player,
    through_on,
    always_on_top_on,
    turn_right,
    move_upper_right,
    through_off,
    always_on_top_off,
  ),
  wait_completion,
  play_se(audio(name: "Door exit", volume: 80)),
  change_tone(tone(-255, -255, -255), frames: 6),
  wait(8),
  transfer_player(map: 18, x: 9, y: 2, direction: :left, fading: false),
  change_tone(tone(0, 0, 0), frames: 6),
]
