# Event 12 "Pokédex" on Pokémon Lab (map 4)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *condition(
    script: "!$player.has_pokedex",
    then: [
      play_me(audio(name: "Item get")),
      text("\\PN received a Pokédex!"),
      script("$player.has_pokedex = true"),
      control_self_switch("A", :ON),
    ],
    else: [
      text("You already have a Pokédex."),
    ],
  ),
]

page 1, []
