# Event 7 "Battle recorder" on Battle Tower (map 55)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *condition(
    character: player,
    facing: :up,
    then: [
      *show_choices(
        choices: ["Play recorded battle", "Exit"],
        cancellation: 2,
        choice1: [
          *condition(
            script: "$PokemonGlobal.lastbattle != nil",
            then: [
              script("pbPlayLastBattle"),
            ],
            else: [
              text("There is no battle recorded."),
            ],
          ),
        ],
      ),
    ],
  ),
]
