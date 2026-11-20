# Event 9 "Door" on Pokémon League entrance (map 36)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  script("$stats.elite_four_attempts += 1"),
  play_se(audio(name: "Door exit", volume: 80)),
  change_tone(tone(-255, -255, -255), frames: 6),
  wait(8),
  transfer_player(map: 37, x: 6, y: 12, direction: :up, fading: false),
  change_tone(tone(0, 0, 0), frames: 6),
]

page 1, [
  *condition(
    script: "get_self.onEvent?",
    then: [
      script("Followers.hide_followers"),
      *move_route(
        player,
        move_down,
        skippable: true,
      ),
      wait_completion,
      script("Followers.put_followers_on_player"),
    ],
  ),
  script("setTempSwitchOn(\"A\")"),
]
