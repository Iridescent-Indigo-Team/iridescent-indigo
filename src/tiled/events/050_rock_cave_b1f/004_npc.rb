# Event 4 "NPC" on Rock Cave B1F (map 50)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  text("\\bHello! I'm the Ruin Maniac!"),
  text("\\bDo you want to dig for buried treasure?"),
  *show_choices(
    choices: ["Yes", "No"],
    cancellation: 2,
    choice1: [
      text("\\bGrand! Let's dig into this wall."),
      *condition(
        character: player,
        facing: :right,
        then: [
          *move_route(
            player,
            move_down,
            move_right,
          ),
          *move_route(
            this,
            turn_down,
          ),
          wait_completion,
        ],
        else: [
          *move_route(
            player,
            turn_right,
          ),
          wait_completion,
        ],
      ),
      script("pbMiningGame"),
    ],
    choice2: [
      text("\\bNo? Alright then."),
    ],
  ),
  *text(
    "\\bWhen using this mining minigame, it is ",
    "recommended that you limit how often the player can ",
    "play it, to prevent them gaining lots of items for free.",
  ),
]
