# Event 6 "Battle Factory door" on Battle Frontier (map 52)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  play_se(audio(name: "Door exit", volume: 80)),
  change_transparent_flag(:transparent),
  script("Followers.follow_into_door"),
  wait_completion,
  change_tone(tone(-255, -255, -255), frames: 6),
  wait(8),
  change_transparent_flag(:normal),
  transfer_player(map: 62, x: 6, y: 8, direction: :up, fading: false),
  change_tone(tone(0, 0, 0), frames: 6),
]

page 1, [
  *condition(
    script: "get_self.onEvent?",
    then: [
      script("Followers.hide_followers"),
      *move_route(
        player,
        route_play_se(audio(name: "Door exit", volume: 80)),
        move_down,
        skippable: true,
      ),
      wait_completion,
      script("Followers.put_followers_on_player"),
    ],
  ),
  script("setTempSwitchOn(\"A\")"),
]
