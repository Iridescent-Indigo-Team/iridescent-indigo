# Event 5 "Trainer(2)" on Route 3 (map 31)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  raw(355, 0, "pbTrainerIntro(:CAMPER)"),
  raw(355, 0, "pbNoticePlayer(get_self)"),
  raw(101, 0, "\\bDid I notice you, or did you notice me?"),
  raw(355, 0, "pbTrainerCheck(:CAMPER,\"Jeff\", 2)"),
  raw(111, 0, 12, "TrainerBattle.start(:CAMPER, \"Jeff\")"),
  raw(111, 1, 12, "Phone.can_add?(:CAMPER, \"Jeff\")"),
  raw(101, 2, "\\bShall we exchange numbers, so we can have a "),
  raw(401, 2, "rematch?"),
  raw(102, 2, ["Yes", "No"], 2, [0, 1, 2, 3]),
  raw(402, 2, 0, "Yes"),
  raw(355, 3, "Phone.add(get_self,"),
  raw(655, 3, "  :CAMPER, \"Jeff\", 2"),
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
  script("pbTrainerIntro(:CAMPER)"),
  text("\\bLet's have a rematch!"),
  *condition(
    script: "Phone.battle(:CAMPER, \"Jeff\")",
    then: [
      *script(
        <<~'CODE'
        Phone.reset_after_win(
          :CAMPER, "Jeff"
        )
        CODE
      ),
      control_self_switch("A", :ON),
      script("pbTrainerEnd"),
    ],
  ),
]

page 2, [
  raw(111, 0, 12, "Phone.variant(:CAMPER, \"Jeff\") == 0"),
  raw(101, 1, "\\bI'll get even stronger, and beat you next time!"),
  raw(0, 1),
  raw(412, 0),
  raw(111, 0, 12, "Phone.variant(:CAMPER, \"Jeff\") >= 1"),
  raw(101, 1, "\\bI don't think I'll ever be able to beat you."),
  raw(0, 1),
  raw(412, 0),
  raw(111, 0, 12, "Phone.can_add?(:CAMPER, \"Jeff\")"),
  raw(101, 1, "\\bShall we exchange numbers, so we can have a "),
  raw(401, 1, "rematch?"),
  raw(102, 1, ["Yes", "No"], 2, [0, 1, 2, 3]),
  raw(402, 1, 0, "Yes"),
  raw(355, 2, "Phone.add(get_self,"),
  raw(655, 2, "  :CAMPER, \"Jeff\", 2"),
  raw(655, 2, ")"),
  raw(0, 2),
  raw(402, 1, 1, "No"),
  raw(0, 2),
  raw(404, 1),
  raw(0, 1),
  raw(412, 0),
]
