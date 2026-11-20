# Event 21 "Coin Case giver" on Game Corner (map 13)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  text("\\rWelcome!"),
  *condition(
    script: "!$bag.has?(:COINCASE)",
    then: [
      text("\\rOh, you don't have a Coin Case? Here."),
      *condition(
        script: "pbReceiveItem(:COINCASE)",
        then: [
          *text(
            "\\rYou can exchange your coins for fabulous prizes ",
            "next door.",
          ),
        ],
        else: [
          *text(
            "\\rYou don't have any room for it. Come back when ",
            "you do.",
          ),
        ],
      ),
    ],
    else: [
      *text(
        "\\rYou can exchange your coins for fabulous prizes ",
        "next door.",
      ),
    ],
  ),
]
