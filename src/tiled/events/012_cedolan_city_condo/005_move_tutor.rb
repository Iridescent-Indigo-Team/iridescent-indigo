# Event 5 "Move Tutor" on Cedolan City Condo (map 12)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  text("\\rHello! I'm a Move Tutor!"),
  *text(
    "\\rI can teach a special and powerful move to your ",
    "Pokémon.",
  ),
  label("Start"),
  text("\\rWhich special move would you like me to teach?"),
  *show_choices(
    choices: ["Frenzy Plant", "Blast Burn", "Hydro Cannon", "Exit"],
    cancellation: 4,
    choice1: [
      *condition(
        script: "pbMoveTutorChoose(:FRENZYPLANT)",
        then: [
          *text(
            "\\rWould you like me to teach another Pokémon a ",
            "special move?",
          ),
          *show_choices(
            choices: ["Yes", "No"],
            cancellation: 2,
            choice1: [
              jump_label("Start"),
            ],
          ),
        ],
        else: [
          jump_label("Start"),
        ],
      ),
    ],
    choice2: [
      *condition(
        script: "pbMoveTutorChoose(:BLASTBURN)",
        then: [
          *text(
            "\\rWould you like me to teach another Pokémon a ",
            "special move?",
          ),
          *show_choices(
            choices: ["Yes", "No"],
            cancellation: 2,
            choice1: [
              jump_label("Start"),
            ],
          ),
        ],
        else: [
          jump_label("Start"),
        ],
      ),
    ],
    choice3: [
      *condition(
        script: "pbMoveTutorChoose(:HYDROCANNON)",
        then: [
          *text(
            "\\rWould you like me to teach another Pokémon a ",
            "special move?",
          ),
          *show_choices(
            choices: ["Yes", "No"],
            cancellation: 2,
            choice1: [
              jump_label("Start"),
            ],
          ),
        ],
        else: [
          jump_label("Start"),
        ],
      ),
    ],
  ),
  text("\\rCome back any time!"),
]
