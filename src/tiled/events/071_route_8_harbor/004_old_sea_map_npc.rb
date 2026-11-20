# Event 4 "Old Sea Map NPC" on Route 8 harbor (map 71)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *condition(
    script: "$bag.has?(:OLDSEAMAP)",
    then: [
      *text(
        "\\bI've already given you an Old Sea Map. Have you ",
        "gone to Faraday Island yet?",
      ),
    ],
    else: [
      text("\\bHere, have this Old Sea Map."),
      *condition(
        script: "pbReceiveItem(:OLDSEAMAP)",
        then: [
          text("\\bYou can use that to sail to Faraday Island."),
        ],
        else: [
          text("\\bOh, you don't have any space in your Bag for it."),
        ],
      ),
    ],
  ),
]
