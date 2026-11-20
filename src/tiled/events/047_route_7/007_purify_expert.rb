# Event 7 "Purify expert" on Route 7 (map 47)
# Page settings (conditions, graphic, trigger, movement) are on the event's
# object in Tiled. See docs/TILED.md for the commands.

page 0, [
  *text(
    "\\bI can tell you some things about Shadow Pokémon",
    "in Essentials. However, the wiki has far more ",
    "information about them.",
  ),
  label("Choices"),
  text("\\bWhat do you want to know?"),
  *show_choices(
    choices: ["Information", "Shadow Pokémon battles", "Purifying Pokémon", "Exit"],
    cancellation: 4,
    choice1: [
      *text(
        "\\bShadow Pokémon are a special kind of Pokémon ",
        "which appeared in Pokémon Colosseum and ",
        "Pokémon XD.",
      ),
      *text(
        "\\bThey can be included in Essentials as well. See ",
        "the wiki for information on how to do this.",
      ),
      jump_label("Choices"),
    ],
    choice2: [
      *text(
        "\\bTrainers with Shadow Pokémon are set up in ",
        "exactly the same way as any other trainer.",
      ),
      *text(
        "\\bAny Poké Ball can be defined as a Snag Ball in ",
        "items.txt. If $player.has_snag_machine is TRUE, ",
        "all types of Poké Ball will be Snag Balls automatically.",
      ),
      script("$player.has_snag_machine = true"),
      *text(
        "\\b$player.pokedex.owned_shadow is an array ",
        "that keeps track of which Shadow Pokémon species ",
        "have been caught.",
      ),
      jump_label("Choices"),
    ],
    choice3: [
      text("\\bYou can purify Shadow Pokémon in two ways."),
      *text(
        "\\bThe first is by bringing them to the Relic Stone here, ",
        "as in Pokémon Colosseum.",
      ),
      *text(
        "\\bThe second is by placing them in the Purify ",
        "Chamber, as in Pokémon XD. You can access it from ",
        "the PC in Poké Centers.",
      ),
      *condition(
        script: "!$player.seen_purify_chamber",
        then: [
          text("\\bI've now given you access to the Purify Chamber."),
          script("$player.seen_purify_chamber = true"),
        ],
      ),
      *text(
        "\\bThe effects of Heart Gauge-lowering items are ",
        "already in Essentials. You just need to add the items ",
        "themselves via a PBS file.",
      ),
      jump_label("Choices"),
    ],
  ),
]
