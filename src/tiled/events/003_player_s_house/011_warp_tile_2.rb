# Event 11 "Warp tile 2" on Player's house (map 3)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  text("Choose a destination."),
  *show_choices(
    choices: ["Game Corner", "Trainer area", "Shadow Pokémon area"],
    cancellation: 0,
    choice1: [
      change_tone(tone(-255, -255, -255), frames: 6),
      wait(8),
      transfer_player(map: 13, x: 9, y: 13, direction: :up, fading: false),
      change_tone(tone(0, 0, 0), frames: 6),
    ],
    choice2: [
      change_tone(tone(-255, -255, -255), frames: 6),
      wait(8),
      transfer_player(map: 31, x: 10, y: 18, direction: :up, fading: false),
      change_tone(tone(0, 0, 0), frames: 6),
    ],
    choice3: [
      change_tone(tone(-255, -255, -255), frames: 6),
      wait(8),
      transfer_player(map: 47, x: 16, y: 21, direction: :down, fading: false),
      change_tone(tone(0, 0, 0), frames: 6),
    ],
  ),
  *show_choices(
    choices: ["Bridges map", "Water map"],
    cancellation: 0,
    choice1: [
      change_tone(tone(-255, -255, -255), frames: 6),
      wait(8),
      transfer_player(map: 21, x: 16, y: 26, direction: :down, fading: false),
      change_tone(tone(0, 0, 0), frames: 6),
    ],
    choice2: [
      change_tone(tone(-255, -255, -255), frames: 6),
      wait(8),
      transfer_player(map: 69, x: 28, y: 12, direction: :down, fading: false),
      change_tone(tone(0, 0, 0), frames: 6),
    ],
  ),
  *show_choices(
    choices: ["Harbor", "Cycle Road", "Cancel"],
    cancellation: 3,
    choice1: [
      change_tone(tone(-255, -255, -255), frames: 6),
      wait(8),
      transfer_player(map: 71, x: 8, y: 3, direction: :down, fading: false),
      change_tone(tone(0, 0, 0), frames: 6),
    ],
    choice2: [
      change_tone(tone(-255, -255, -255), frames: 6),
      wait(8),
      transfer_player(map: 46, x: 11, y: 6, direction: :left, fading: false),
      change_tone(tone(0, 0, 0), frames: 6),
    ],
  ),
]
