# Event 17 "Cave entrance" on Route 3 (map 31)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  play_se(audio(name: "Door exit", volume: 80)),
  change_tone(tone(255, 255, 255, 255), frames: 6),
  wait(8),
  script("pbCaveEntrance"),
  transfer_player(map: 34, x: 23, y: 17, direction: :up, fading: false),
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
