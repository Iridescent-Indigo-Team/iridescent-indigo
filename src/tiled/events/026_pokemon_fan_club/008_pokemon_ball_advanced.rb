# Event 8 "Pokémon ball - Advanced" on Pokémon Fan Club (map 26)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *comment(
    "This is an example of giving a Pokémon which has ",
    "been modified. The Pokémon is defined separately ",
    "before being given to the player.",
  ),
  *condition(
    script: "!pbBoxesFull?",
    then: [
      *script(
        <<~'CODE'
        pkmn = Pokemon.new(:PICHU, 30)
        pkmn.item = :ZAPPLATE
        pkmn.form = 2           # Spiky-eared
        pkmn.makeFemale
        pkmn.shiny = false
        pkmn.learn_move(:VOLTTACKLE)
        pkmn.learn_move(:HELPINGHAND)
        pkmn.learn_move(:SWAGGER)
        pkmn.learn_move(:PAINSPLIT)
        pkmn.calc_stats
        CODE
      ),
      script("pbAddPokemon(pkmn)"),
      control_self_switch("A", :ON),
    ],
    else: [
      text("There's no more room for Pokémon!"),
      text("The Pokémon Boxes are full and can't accept any more!"),
    ],
  ),
]

page 1, []
