# Event 1 "Warp NPC" on Tiall Region (map 75)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  text("\\bThis is the Tiall Region."),
  text("\\bDo you want to go back to the Essen Region?"),
  *show_choices(
    choices: ["Yes", "No"],
    cancellation: 2,
    choice1: [
      play_se(audio(name: "Door exit", volume: 80)),
      change_tone(tone(-255, -255, -255), frames: 6),
      wait(8),
      transfer_player(map: 71, x: 8, y: 5, direction: :up, fading: false),
      change_tone(tone(0, 0, 0), frames: 6),
    ],
    choice2: [
      text("\\bLet me know if you do."),
    ],
  ),
]
