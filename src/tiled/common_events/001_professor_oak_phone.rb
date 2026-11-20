# Common event 1: Professor Oak phone
common(
  id: 1,
  name: "Professor Oak phone",
  trigger: :none,
  switch: 1,
  commands: [
    script("Phone::Call.start_message"),
    *condition(
      script: "$game_map.map_id==4",
      then: [
        text("\\bHello, \\PN!\\nI can see you calling me over there!"),
        text("\\bCome over and talk to me."),
        jump_label("End call"),
      ],
    ),
    text("\\bHello, this is Professor Oak...\\nOh, hello, \\PN!"),
    text("\\bSo, how's your Pokédex coming along?"),
    *show_choices(
      choices: ["Evaluate Pokédex", "Quit"],
      cancellation: 2,
      choice1: [
        *script(
          <<~'CODE'
          pbSet(1,$player.pokedex.seen_count)
          pbSet(2,$player.pokedex.owned_count)
          CODE
        ),
        *text(
          "\\bHmm, let's see..\\nYou've seen \\v[1] Pokémon, and",
          "\\nyou've caught \\v[2] Pokémon!\\nI see!",
        ),
        *condition(
          variable: v(2),
          operation: "<",
          constant: 30,
          then: [
            *text(
              "\\bHmm, you still have a long journey ahead of you!",
              "\\nKeep on going!",
            ),
            jump_label("End evaluation"),
          ],
        ),
        *condition(
          variable: v(2),
          operation: "<",
          constant: 75,
          then: [
            text("\\bHmm, you're catching Pokémon at a decent pace!"),
            jump_label("End evaluation"),
          ],
        ),
        *condition(
          variable: v(2),
          operation: "<",
          constant: 150,
          then: [
            *text(
              "\\bYou've caught a lot of Pokémon, but make sure ",
              "you're raising them carefully!",
            ),
            jump_label("End evaluation"),
          ],
        ),
        *condition(
          variable: v(2),
          operation: ">=",
          constant: 150,
          then: [
            text("\\bI didn't even know that many Pokémon existed!"),
            jump_label("End evaluation"),
          ],
        ),
        label("End evaluation"),
        text("\\bShow me your Pokédex again anytime!"),
      ],
      choice2: [
        text("\\bShow me your Pokédex anytime!"),
      ],
    ),
    label("End call"),
    script("Phone::Call.end_message"),
  ],
)
