# Event 8 "Mart" on Pokémon League entrance (map 36)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *condition(
    script: "$player.badge_count >= 8",
    then: [
      *script(
        <<~'CODE'
        pbPokemonMart([
          :POKEBALL, :GREATBALL, :ULTRABALL,
          :POTION, :SUPERPOTION,
          :HYPERPOTION, :MAXPOTION,
          :FULLRESTORE, :REVIVE,
          :ANTIDOTE, :PARALYZEHEAL,
          :AWAKENING, :BURNHEAL, :ICEHEAL,
          :FULLHEAL,
          :ESCAPEROPE,
          :REPEL, :SUPERREPEL, :MAXREPEL
        ])
        CODE
      ),
      exit_event_processing,
    ],
  ),
  *condition(
    script: "$player.badge_count >= 7",
    then: [
      *script(
        <<~'CODE'
        pbPokemonMart([
          :POKEBALL, :GREATBALL, :ULTRABALL,
          :POTION, :SUPERPOTION,
          :HYPERPOTION, :MAXPOTION,
          :REVIVE,
          :ANTIDOTE, :PARALYZEHEAL,
          :AWAKENING, :BURNHEAL, :ICEHEAL,
          :FULLHEAL,
          :ESCAPEROPE,
          :REPEL, :SUPERREPEL, :MAXREPEL
        ])
        CODE
      ),
      exit_event_processing,
    ],
  ),
  *condition(
    script: "$player.badge_count >= 5",
    then: [
      *script(
        <<~'CODE'
        pbPokemonMart([
          :POKEBALL, :GREATBALL, :ULTRABALL,
          :POTION, :SUPERPOTION,
          :HYPERPOTION,
          :REVIVE,
          :ANTIDOTE, :PARALYZEHEAL,
          :AWAKENING, :BURNHEAL, :ICEHEAL,
          :FULLHEAL,
          :ESCAPEROPE,
          :REPEL, :SUPERREPEL, :MAXREPEL
        ])
        CODE
      ),
      exit_event_processing,
    ],
  ),
  *condition(
    script: "$player.badge_count >= 3",
    then: [
      *script(
        <<~'CODE'
        pbPokemonMart([
          :POKEBALL, :GREATBALL,
          :POTION, :SUPERPOTION,
          :HYPERPOTION,
          :REVIVE,
          :ANTIDOTE, :PARALYZEHEAL,
          :AWAKENING, :BURNHEAL, :ICEHEAL,
          :ESCAPEROPE,
          :REPEL, :SUPERREPEL
        ])
        CODE
      ),
      exit_event_processing,
    ],
  ),
  *condition(
    script: "$player.badge_count >= 1",
    then: [
      *script(
        <<~'CODE'
        pbPokemonMart([
          :POKEBALL, :GREATBALL,
          :POTION, :SUPERPOTION,
          :ANTIDOTE, :PARALYZEHEAL,
          :AWAKENING, :BURNHEAL, :ICEHEAL,
          :ESCAPEROPE,
          :REPEL
        ])
        CODE
      ),
      exit_event_processing,
    ],
  ),
  *script(
    <<~'CODE'
    pbPokemonMart([
      :POKEBALL,
      :POTION
    ])
    CODE
  ),
]
