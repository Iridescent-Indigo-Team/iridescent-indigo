# Event 3 "Aurora Ticket NPC" on Route 8 harbor (map 71)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *condition(
    script: "$bag.has?(:AURORATICKET)",
    then: [
      *text(
        "\\bI've already given you an Aurora Ticket. Have you ",
        "gone to Berth Island yet?",
      ),
    ],
    else: [
      text("\\bHere, have this Aurora Ticket."),
      *condition(
        script: "pbReceiveItem(:AURORATICKET)",
        then: [
          text("\\bYou can use that to sail to Berth Island."),
        ],
        else: [
          text("\\bOh, you don't have any space in your Bag for it."),
        ],
      ),
    ],
  ),
]
