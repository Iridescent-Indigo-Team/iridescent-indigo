# Event 1 "Exit" on Cedolan Dept. Elevator (map 20)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  play_se(audio(name: "Door exit", volume: 80)),
  change_tone(tone(-255, -255, -255), frames: 6),
  wait(8),
  *condition(
    variable: v(10),
    operation: "==",
    constant: 5,
    then: [
      transfer_player(map: 18, x: 6, y: 1, direction: :retain, fading: false),
    ],
    else: condition(
      variable: v(10),
      operation: "==",
      constant: 4,
      then: [
        transfer_player(map: 17, x: 6, y: 1, direction: :retain, fading: false),
      ],
      else: condition(
        variable: v(10),
        operation: "==",
        constant: 3,
        then: [
          transfer_player(map: 16, x: 6, y: 1, direction: :retain, fading: false),
        ],
        else: condition(
          variable: v(10),
          operation: "==",
          constant: 2,
          then: [
            transfer_player(map: 15, x: 6, y: 1, direction: :retain, fading: false),
          ],
          else: [
            transfer_player(map: 14, x: 6, y: 1, direction: :retain, fading: false),
          ],
        ),
      ),
    ),
  ),
  change_tone(tone(0, 0, 0), frames: 6),
]
