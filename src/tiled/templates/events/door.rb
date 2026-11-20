# Template: door. Opens, lets the player through and transfers them.
# Parameters:
#   to    - name of the map to go to (as in the map registry)
#   spawn - name of a Spawn object on that map where the player arrives

page 0, [
  *move_route(
    this,
    route_play_se(audio(name: "Door enter")),
    route_wait(2),
    turn_left,
    route_wait(2),
    turn_right,
    route_wait(2),
    turn_up,
    route_wait(2),
    skippable: true,
  ),
  wait_completion,
  *move_route(
    player,
    through_on,
    move_up,
    through_off,
    skippable: true,
  ),
  wait_completion,
  change_transparent_flag(:transparent),
  script("Followers.follow_into_door"),
  wait_completion,
  *move_route(
    this,
    route_wait(2),
    turn_right,
    route_wait(2),
    turn_left,
    route_wait(2),
    turn_down,
    route_wait(2),
    skippable: true,
  ),
  wait_completion,
  change_tone(tone(-255, -255, -255), frames: 6),
  wait(8),
  change_transparent_flag(:normal),
  transfer(to: param(:to), spawn: param(:spawn), fading: false),
  change_tone(tone(0, 0, 0), frames: 6),
]
