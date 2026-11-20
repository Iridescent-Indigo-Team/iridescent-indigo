# Event 6 "Trainer(2)" on Route 3 (map 31)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  raw(355, 0, "pbTrainerIntro(:PICNICKER)"),
  raw(355, 0, "pbNoticePlayer(get_self)"),
  raw(101, 0, "\\rBattle me now!"),
  raw(355, 0, "pbTrainerCheck("),
  raw(655, 0, "  :PICNICKER, \"Susie\", 2"),
  raw(655, 0, ")"),
  raw(111, 0, 12, "TrainerBattle.start(:PICNICKER, \"Susie\")"),
  raw(111, 1, 12, "Phone.can_add?(:PICNICKER, \"Susie\")"),
  raw(101, 2, "\\rCan I add you to my contacts list?"),
  raw(102, 2, ["Yes", "No"], 2, [0, 1, 2, 3]),
  raw(402, 2, 0, "Yes"),
  raw(355, 3, "Phone.add(get_self,"),
  raw(655, 3, "  :PICNICKER, \"Susie\", 2"),
  raw(655, 3, ")"),
  raw(0, 3),
  raw(402, 2, 1, "No"),
  raw(0, 3),
  raw(404, 2),
  raw(0, 2),
  raw(412, 1),
  raw(123, 1, "A", 0),
  raw(123, 1, "B", 0),
  raw(0, 1),
  raw(412, 0),
  raw(355, 0, "pbTrainerEnd"),
]

page 1, [
  script("pbTrainerIntro(:PICNICKER)"),
  text("\\rBattle me now!"),
  *condition(
    script: "Phone.battle(:PICNICKER, \"Susie\")",
    then: [
      *script(
        <<~'CODE'
        Phone.reset_after_win(
          :PICNICKER, "Susie"
        )
        CODE
      ),
      control_self_switch("A", :ON),
      script("pbTrainerEnd"),
    ],
  ),
]

page 2, [
  raw(111, 0, 12, "Phone.variant(:PICNICKER, \"Susie\") == 0"),
  raw(101, 1, "\\rI say the same thing after every battle. Why? Just "),
  raw(401, 1, "because."),
  raw(0, 1),
  raw(412, 0),
  raw(111, 0, 12, "Phone.variant(:PICNICKER, \"Susie\") >= 1"),
  raw(101, 1, "\\rI say the same thing after every battle. Why? Just "),
  raw(401, 1, "because."),
  raw(0, 1),
  raw(412, 0),
  raw(111, 0, 12, "Phone.can_add?(:PICNICKER, \"Susie\")"),
  raw(101, 1, "\\rCan I add you to my contacts list?"),
  raw(102, 1, ["Yes", "No"], 2, [0, 1, 2, 3]),
  raw(402, 1, 0, "Yes"),
  raw(355, 2, "Phone.add(get_self,"),
  raw(655, 2, "  :PICNICKER, \"Susie\", 2"),
  raw(655, 2, ")"),
  raw(0, 2),
  raw(402, 1, 1, "No"),
  raw(0, 2),
  raw(404, 1),
  raw(0, 1),
  raw(412, 0),
]
