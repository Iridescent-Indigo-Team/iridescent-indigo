# Event 3 "Questionnaire" on Lerucean Town Mart (map 25)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *condition(
    script: "$player.mystery_gift_unlocked",
    else: [
      text("There is a questionnaire.\\nWould you like to fill it out?"),
      *show_choices(
        choices: ["Yes", "No"],
        cancellation: 2,
        choice1: [
          text("\\PN filled in the questionnaire."),
          *move_route(
            character(2),
            turn_down,
          ),
          script("pbExclaim(get_character(2))"),
          wait(20),
          text("\\bOh, hello!\\nYou filled in the questionnaire?"),
          text("\\bThat means you must know about the Mystery Gift."),
          *text(
            "\\bFrom now on, you should be receiving Mystery ",
            "Gifts!",
          ),
          script("$player.mystery_gift_unlocked = true"),
          *text(
            "\\w[signskin]Once you save your game, you can ",
            "access the Mystery Gift.",
          ),
        ],
      ),
    ],
  ),
]
