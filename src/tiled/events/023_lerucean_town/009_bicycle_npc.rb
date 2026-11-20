# Event 9 "Bicycle NPC" on Lerucean Town (map 23)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  raw(108, 0, "This NPC swaps a Lemonade for a Bicycle (because "),
  raw(408, 0, "Essentials doesn't come with a Bike Voucher item)."),
  raw(101, 0, "\\bHi! I'm super thirsty. Do you have a Lemonade? I'll "),
  raw(401, 0, "trade you a Bicycle for one. I have too many "),
  raw(401, 0, "Bicycles."),
  raw(111, 0, 12, "$bag.has?(:LEMONADE)"),
  raw(101, 1, "\\bOh, you have a Lemonade? Would you consider "),
  raw(401, 1, "exchanging it for a Bicycle?"),
  raw(102, 1, ["Yes", "No"], 2),
  raw(402, 1, 0, "Yes"),
  raw(101, 2, "\\bExcellent! Here you go."),
  raw(111, 2, 12, "pbReceiveItem(:BICYCLE)"),
  raw(108, 3, "There is no need to check whether it's possible to "),
  raw(408, 3, "delete a Lemonade from the player's Bag, because "),
  raw(408, 3, "the check above made sure there is at least one of "),
  raw(408, 3, "them in the Bag, so it can definitely be deleted."),
  raw(355, 3, "$bag.remove(:LEMONADE)"),
  raw(101, 3, "\\bThank you! I really needed this."),
  raw(123, 3, "A", 0),
  raw(0, 3),
  raw(411, 2),
  raw(101, 3, "\\bYou have no space in your Bag. I don't want to just "),
  raw(401, 3, "take your Lemonade, so come back when I can give "),
  raw(401, 3, "you a Bicycle in return."),
  raw(0, 3),
  raw(412, 2),
  raw(0, 2),
  raw(402, 1, 1, "No"),
  raw(101, 2, "\\bThat's too bad. I really am thirsty."),
  raw(0, 2),
  raw(404, 1),
  raw(0, 1),
  raw(411, 0),
  raw(0, 1),
  raw(412, 0),
]

page 1, [
  *text(
    "\\bAre you enjoying your Bicycle? The Lemonade you ",
    "gave me was just what I needed.",
  ),
]
