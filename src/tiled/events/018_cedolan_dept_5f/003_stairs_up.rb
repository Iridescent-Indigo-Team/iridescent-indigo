# Event 3 "Stairs up" on Cedolan Dept. 5F (map 18)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *move_route(
    player,
    through_on,
    always_on_top_on,
    turn_left,
    move_upper_left,
    through_off,
    always_on_top_off,
  ),
  wait_completion,
  play_se(audio(name: "Door exit", volume: 80)),
  change_tone(tone(-255, -255, -255), frames: 6),
  wait(8),
  transfer_player(map: 19, x: 22, y: 10, direction: :retain, fading: false),
  change_tone(tone(0, 0, 0), frames: 6),
]
