# Event 2 "Sailor" on Route 8 harbor (map 71)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *script(
    <<~'CODE'
    hide_choice(2,
      !$bag.has?(:AURORATICKET))
    hide_choice(3,
      !$bag.has?(:OLDSEAMAP))
    CODE
  ),
  text("\\bAhoy, there!\\nWhere do you want to sail?"),
  *show_choices(
    choices: ["Tiall Region", "Berth Island", "Faraday Island", "Exit"],
    cancellation: 4,
    choice1: [
      text("\\bThe Tiall Region it is. All aboard!"),
      *move_route(
        character(2),
        through_on,
        move_down,
        change_opacity(0),
        through_off,
      ),
      *move_route(
        player,
        through_on,
        move_down,
        move_down,
        through_off,
      ),
      wait_completion,
      play_se(audio(name: "Door exit", volume: 80)),
      change_transparent_flag(:transparent),
      change_tone(tone(-255, -255, -255), frames: 6),
      wait(8),
      change_transparent_flag(:normal),
      transfer_player(map: 75, x: 17, y: 11, direction: :down, fading: false),
      change_tone(tone(0, 0, 0), frames: 6),
    ],
    choice2: [
      text("\\bBerth Island it is. All aboard!"),
      control_switches(s(51), :ON),
      *move_route(
        character(2),
        through_on,
        move_down,
        change_opacity(0),
        through_off,
      ),
      *move_route(
        player,
        through_on,
        move_down,
        move_down,
        through_off,
      ),
      wait_completion,
      play_se(audio(name: "Door exit", volume: 80)),
      change_transparent_flag(:transparent),
      change_tone(tone(-255, -255, -255), frames: 6),
      wait(8),
      change_transparent_flag(:normal),
      transfer_player(map: 72, x: 14, y: 23, direction: :up, fading: false),
      change_tone(tone(0, 0, 0), frames: 6),
    ],
    choice3: [
      text("\\bFaraday Island it is. All aboard!"),
      control_switches(s(52), :ON),
      *move_route(
        character(2),
        through_on,
        move_down,
        change_opacity(0),
        through_off,
      ),
      *move_route(
        player,
        through_on,
        move_down,
        move_down,
        through_off,
      ),
      wait_completion,
      play_se(audio(name: "Door exit", volume: 80)),
      change_transparent_flag(:transparent),
      change_tone(tone(-255, -255, -255), frames: 6),
      wait(8),
      change_transparent_flag(:normal),
      transfer_player(map: 73, x: 14, y: 23, direction: :up, fading: false),
      change_tone(tone(0, 0, 0), frames: 6),
    ],
    choice4: [
      text("\\bLet me know if you want to set sail."),
    ],
  ),
]
