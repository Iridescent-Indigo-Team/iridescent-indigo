# Event 4 "Deliveryman" on Lerucean Town Mart (map 25)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, []

page 1, [
  *condition(
    script: "pbNextMysteryGiftID > 0",
    then: [
      text("\\bHello. You must be \\PN."),
      text("\\bI've received a gift for you.\\nHere you go!"),
      *script(
        <<~'CODE'
        id = pbNextMysteryGiftID
        pbReceiveMysteryGift(id)
        CODE
      ),
    ],
    else: [
      text("\\bI haven't received any other gifts for you."),
    ],
  ),
  text("\\bWe look forward to your next visit."),
]
