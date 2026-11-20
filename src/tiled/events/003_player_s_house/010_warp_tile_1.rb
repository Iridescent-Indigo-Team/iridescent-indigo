# Event 10 "Warp tile 1" on Player's house (map 3)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  text("Choose a destination."),
  *show_choices(
    choices: ["Poké Center", "Poké Mart", "Pokémon Gym", "Day Care"],
    cancellation: 0,
    choice1: [
      change_tone(tone(-255, -255, -255), frames: 6),
      wait(8),
      transfer_player(map: 9, x: 7, y: 8, direction: :up, fading: false),
      change_tone(tone(0, 0, 0), frames: 6),
    ],
    choice2: [
      change_tone(tone(-255, -255, -255), frames: 6),
      wait(8),
      transfer_player(map: 25, x: 4, y: 7, direction: :up, fading: false),
      change_tone(tone(0, 0, 0), frames: 6),
    ],
    choice3: [
      change_tone(tone(-255, -255, -255), frames: 6),
      wait(8),
      transfer_player(map: 10, x: 6, y: 14, direction: :up, fading: false),
      change_tone(tone(0, 0, 0), frames: 6),
    ],
    choice4: [
      change_tone(tone(-255, -255, -255), frames: 6),
      wait(8),
      transfer_player(map: 27, x: 4, y: 7, direction: :up, fading: false),
      change_tone(tone(0, 0, 0), frames: 6),
    ],
  ),
  *show_choices(
    choices: ["Cave", "Safari Zone", "Bug Catching Contest", "Battle Frontier"],
    cancellation: 0,
    choice1: [
      change_tone(tone(-255, -255, -255), frames: 6),
      wait(8),
      transfer_player(map: 49, x: 12, y: 14, direction: :up, fading: false),
      change_tone(tone(0, 0, 0), frames: 6),
    ],
    choice2: [
      change_tone(tone(-255, -255, -255), frames: 6),
      wait(8),
      transfer_player(map: 67, x: 4, y: 7, direction: :up, fading: false),
      change_tone(tone(0, 0, 0), frames: 6),
    ],
    choice3: [
      change_tone(tone(-255, -255, -255), frames: 6),
      wait(8),
      transfer_player(map: 29, x: 1, y: 5, direction: :right, fading: false),
      change_tone(tone(0, 0, 0), frames: 6),
    ],
    choice4: [
      change_tone(tone(-255, -255, -255), frames: 6),
      wait(8),
      transfer_player(map: 52, x: 18, y: 16, direction: :down, fading: false),
      change_tone(tone(0, 0, 0), frames: 6),
    ],
  ),
  *show_choices(
    choices: ["Cancel"],
    cancellation: 1,
  ),
]
