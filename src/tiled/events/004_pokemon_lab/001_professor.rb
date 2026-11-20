# Event 1 "Professor" on Pokémon Lab (map 4)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  raw(101, 0, "\\bOak: You should battle with your Pokémon to make "),
  raw(401, 0, "it strong."),
  raw(111, 0, 12, "$player.has_pokegear"),
  raw(101, 1, "\\bOak: If you register me in your Pokégear, you can "),
  raw(401, 1, "call me any time to rate your Pokédex completion."),
  raw(102, 1, ["Yes", "No"], 2),
  raw(402, 1, 0, "Yes"),
  raw(355, 2, "Phone.add(4, \"Professor Oak\", 1)"),
  raw(101, 2, "\\bOak: Please let me know how you get on!"),
  raw(0, 2),
  raw(402, 1, 1, "No"),
  raw(101, 2, "\\bOak: Oh, okay. Let me know if you change your "),
  raw(401, 2, "mind."),
  raw(0, 2),
  raw(404, 1),
  raw(0, 1),
  raw(411, 0),
  raw(0, 1),
  raw(412, 0),
]

page 1, [
  text("\\bOak: Well, which one do you want?"),
]
