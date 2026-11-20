# Event 5 "Contest ribbon giver" on Daisy's house (map 8)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *comment(
    "Gives or upgrades a contest ribbon for the lead ",
    "Pokémon.",
    "The method upgradeRibbon either upgrades an ",
    "existing ribbon to the next one listed, or gives the ",
    "first ribbon if the Pokémon has none of them.",
    "Returns nil if couldn't add/upgrade a ribbon.",
  ),
  text("\\rHi! I'm the Contest Lady!"),
  text("\\rI give out contest ribbons. Do you want one?"),
  *show_choices(
    choices: ["Yes", "No"],
    cancellation: 2,
    choice1: [
      *script(
        <<~'CODE'
        pkmn = $player.first_pokemon
        ret = pkmn.upgradeRibbon(
          :HOENNCOOL,
          :HOENNCOOLSUPER,
          :HOENNCOOLHYPER,
          :HOENNCOOLMASTER
        )
        CODE
      ),
      *script(
        <<~'CODE'
        pbSet(1, ret || :NONE)
        pbSet(2, pkmn.name)
        if ret
          data = GameData::Ribbon.get(ret)
          pbSet(3, data.name)
        end
        CODE
      ),
      *condition(
        script: "pbGet(1) == :NONE",
        then: [
          *text(
            "\\rSorry, your \\v[2] already has the highest ranked ",
            "Cool Ribbon.",
          ),
        ],
        else: [
          *text(
            "\\PN received the \\v[3].",
            "\\me[Item get]\\wtnp[40]",
          ),
          text("\\PN put the \\v[3] on \\v[2]."),
        ],
      ),
    ],
    choice2: [
      text("\\rThat's your choice."),
    ],
  ),
]
