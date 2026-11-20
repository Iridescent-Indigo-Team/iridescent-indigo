# Event 3 "Brock" on Cedolan Gym (map 10)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  script("$stats.gym_leader_attempts[0] += 1"),
  script("pbTrainerIntro(:LEADER_Brock)"),
  text("\\bYou've made it this far, but can you beat me?"),
  *condition(
    script: "TrainerBattle.start(:LEADER_Brock, \"Brock\")",
    then: [
      *text(
        "\\me[Badge get]\\bYou've earned the Boulder Badge.",
        "\\wtnp[110]",
      ),
      *script(
        <<~'CODE'
        $stats.set_time_to_badge(0)
        $player.badges[0] = true
        CODE
      ),
      text("\\bHere, have this TM too."),
      script("pbReceiveItem(:TM80)"),
      *text(
        "\\bYou may find the Pokémon on Route 1 are a little ",
        "tougher now.",
      ),
      script("$PokemonGlobal.encounter_version = 1"),
      control_switches(s(4), :ON),
      control_self_switch("A", :ON),
    ],
  ),
  script("pbTrainerEnd"),
]

page 1, [
  *text(
    "\\bI often work in the caves on Route 7, digging up ",
    "fossils.",
  ),
  *text(
    "\\bThere's a man in the Pokémon Institute who can ",
    "revive fossils into living Pokémon.",
  ),
]
