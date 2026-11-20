# Marks, titles, sizes and the player's birthday

Pokessentials extends the Essentials ribbon system with the main series'
**marks** and **titles**. Every Pokémon also has a **size scale**, and the
player can have a **birthday**.

- [Ribbons and marks](#ribbons-and-marks)
- [Titles](#titles)
- [How wild Pokémon get marks](#how-wild-pokémon-get-marks)
- [Party marks](#party-marks)
- [The Mark Charm](#the-mark-charm)
- [Size](#size)
- [The player's birthday](#the-players-birthday)
- [Trainers and in-game trades](#trainers-and-in-game-trades)
- [Summary screen](#summary-screen)
- [Debug menu](#debug-menu)
- [Settings](#settings)
- [Script reference](#script-reference)

## Ribbons and marks

Marks are ribbons with `IsMark = true`. Both are defined in
`src/pbs/ribbons.json` (`ribbons.txt`) and stored together in
`Pokemon#ribbons`, so everything that works with ribbons works with marks.

| PBS key | JSON property | Meaning |
| --- | --- | --- |
| `Name`, `IconPosition`, `Description` | `real_name`, `icon_position`, `real_description` | As before. `IconPosition` is the icon's place in `Graphics/UI/Summary/ribbons.png` (8 icons per row; the icon size is the sheet's width / 8). |
| `Title` | `real_title` | The title the ribbon/mark confers, shown after the name ("the Peckish"). |
| `PrefixTitle` | `real_prefix_title` | A title shown before the name instead ("/Owner/'s"). |
| `PreviousRanks` | `previous_ranks` | The lower ranks of this ribbon (e.g. `HOENNCOOL,HOENNCOOLSUPER` for the Hyper rank). Used for ranks and the Contest/Battle Memory Ribbons. |
| `IsMark` | `mark` | `true` for a mark. |
| `Flags` | `flags` | The category: `ContestRibbon`, `LeagueRibbon`, `FrontierRibbon`, `MemorialRibbon`, `GiftRibbon`, `TimeMark`, `WeatherMark`, `EncounterMark`, `RarityMark`, `PersonalityMark`, `SizeMark`, `PartyMark`, `BossMark`. |

Titles can contain tokens: `/Owner/` (the Pokémon's original trainer),
`/Player/` (the player) and `/Variable_N/` (game variable N).

When a Pokémon gets a contest or Battle Frontier ribbon listed in the Contest
or Battle Memory Ribbon's `PreviousRanks`, it also gets that Memory Ribbon,
which turns gold once it has all of them.

Ribbon IDs renamed by the new `ribbons.txt` (the Sinnoh `...SUPER`/`...HYPER`
ranks are now `...GREAT`/`...ULTRA`, and `SINNOHCHAMP` is `SINNOHCHAMPION`)
are converted in old saves (`Pokemon::RENAMED_RIBBONS`). Ribbons that no
longer exist are dropped.

## Titles

A Pokémon can have one ribbon or mark **affixed**; that ribbon's title is shown
with its name when it is sent out in battle:

- "Oh! A wild Pikachu the Peckish appeared!"
- "Go! Pikachu the Peckish!" / "Red sent out Pikachu the Peckish!"
- the messages when switching in.

The affixed ribbon's icon also rises above the Pokémon as it comes out of its
Poké Ball. Shadow Pokémon and eggs never show a title.

```ruby
pkmn.affixed_ribbon = :RAREMARK   # Gives the mark if needed and affixes it
pkmn.affixed_ribbon = nil         # Removes the title
pkmn.title                        # => "the Recluse"
pkmn.name_with_title              # => "Pikachu the Recluse"
```

## How wild Pokémon get marks

Each wild Pokémon rolls for a mark when it is created (the
`:on_wild_pokemon_created` handler in
`src/data/012_Overworld/002_Battle triggering/006_Overworld_Marks.rb`). Each
roll tries these in order and stops at the first success; a Pokémon gets at
most one mark this way.

| Mark | Condition | Odds (`Settings::WILD_MARK_ODDS`) |
| --- | --- | --- |
| Rare Mark | always | 1/1000 |
| A random personality mark | always | 1/100 |
| Uncommon Mark | always | 1/50 |
| Weather marks | the map has overworld weather: Rain/Heavy Rain → Rainy, Storm → Stormy, Snow → Snowy, Blizzard → Blizzard, Sandstorm → Sandstorm, Sun → Dry, Fog → Misty (a `:Cloudy` or `:Overcast` weather, if you add one, gives the Cloudy Mark) | 1/50 |
| Time marks | always: night → Sleepy-Time, morning → Dawn, evening → Dusk, otherwise Lunchtime | 1/50 |
| Fishing Mark | a fishing encounter | 1/25 |
| Curry Mark | the encounter was lured with Sweet Scent or Honey | 1/25 |
| Destiny Mark | **only on the player's birthday** | 1/25 |

Wild Pokémon of the smallest or largest size (scale 0 or 255) always have the
Mini or Jumbo Mark (`Settings::GUARANTEED_WILD_SIZE_MARKS`). A wild Pokémon's
mark is affixed, so it is introduced with its title
(`Settings::AFFIX_WILD_MARK_TITLES`).

Turn on Game Switch 38, "No wild marks" (`Settings::NO_WILD_MARKS_SWITCH`), to
stop wild Pokémon from getting marks, e.g. for a scripted encounter. To roll a
mark for a Pokémon you create yourself, call `pbRollWildMark(pkmn)`.

## Party marks

Pokémon in the party can earn these. The odds are 1 in
`Settings::PARTY_MARK_ODDS` (50) per Pokémon each time, halved by the Mark
Charm.

| Mark | When |
| --- | --- |
| Partner Mark | every `Settings::PARTNER_MARK_STEPS` steps, for able Pokémon with at least `Settings::PARTNER_MARK_HAPPINESS` happiness |
| Itemfinder Mark | the lead Pokémon, when an item ball is picked up (`pbItemBall`) |
| Gourmand Mark | able Pokémon, when berries are picked from a plant or bought |

The boss marks (Alpha, Mightiest, Titan) and any other mark can be given by
events:

```ruby
pbGiveMark(pkmn, :TITANMARK)          # One Pokémon (pass true to affix it too)
pbGiveMarkToParty(:MIGHTIESTMARK, 1)  # Every able party Pokémon (1 in 1 chance)
```

## The Mark Charm

`MARKCHARM` is a Key Item. While the player has it, wild Pokémon roll for a
mark `Settings::MARK_CHARM_EXTRA_ROLLS` (2) extra times, as in the main series,
and party marks are twice as likely. Its graphic is
`Graphics/Items/MARKCHARM.png`.

## Size

Every Pokémon has a size scale, `Pokemon#scale`, from 0 (smallest) to 255
(largest). New Pokémon roll it like the main series (the sum of two random
numbers, so middling sizes are most common); Pokémon from older saves get one
the first time it is read. It doesn't change how the Pokémon looks.

```ruby
pkmn.scale               # => 0..255
pkmn.scale = 255
pkmn.size_category       # => :XXXS, :XXS, :XS, :S, :M, :L, :XL, :XXL or :XXXL
pkmn.size_name           # => "XXXL" (translated)
pkmn.min_size?           # scale 0
pkmn.max_size?           # scale 255
pkmn.scaled_height       # the species' height (in 0.1 m) x 0.8 to 1.2
pkmn.scaled_height_text  # => "0.48 m" (feet and inches in the US)
pkmn.compare_size(other) # -1, 0 or 1 (same species: by scale; otherwise by height)
pkmn.bigger_than?(other)
pkmn.smaller_than?(other)
```

For a "biggest Magikarp" event, `pbCheckPokemonSize` lets the player choose a
party Pokémon, compares it with a saved record and updates the record:

```ruby
result = pbCheckPokemonSize(:MAGIKARP_RECORD, :MAGIKARP)
# result is :new, :bigger, :same, :smaller, or nil if nothing was chosen
pbReceiveItem(:NETBALL) if [:new, :bigger].include?(result)
```

It shows standard messages unless you pass `false` as the third argument.
`pbGetSizeRecord(:MAGIKARP_RECORD)` returns `[species, scale, height, name]`,
and `pbClearSizeRecord` clears a record.

## The player's birthday

The game doesn't ask for the birthday on its own. Call `pbSetPlayerBirthday`
from an event (for example in the intro); it asks for the month and day and
confirms them. `pbSetPlayerBirthday(true)` lets the player cancel.

```ruby
pbSetPlayerBirthday             # Ask the player
$player.set_birthday(3, 14)     # Set it directly (month, day)
$player.birthday_set?
$player.birthday?               # Is it the player's birthday today?
pbPlayerBirthday?               # The same, for Conditional Branch scripts
pbPlayerBirthdayText            # => "March 14"
$player.celebrate_birthday      # true once per birthday, then false until next year
```

A birthday on 29 February counts on 28 February in other years. The Destiny
Mark can only be found on the player's birthday.

A birthday event that gives a present once a year:

```ruby
if $player.celebrate_birthday
  pbMessage(_INTL("Happy birthday! Here's a little something."))
  pbGetPokemon(1).giveRibbon(:BIRTHDAY)
end
```

## Trainers and in-game trades

Trainers' Pokémon (`src/pbs/trainers`, `trainers.txt`) have two more
properties:

| PBS key | JSON property | Meaning |
| --- | --- | --- |
| `Title` | `title` | A ribbon/mark the Pokémon has and shows the title of. It must confer a title. Ignored for Shadow Pokémon. |
| `Scale` | `scale` | The Pokémon's size, 0-255. |

```
Pokemon = PIKACHU,20
    Title = RAREMARK
    Scale = 255
```

Both can be set in the trainer editor in the Debug menu.

`pbStartTrade` takes `title:` and `scale:` for the Pokémon the player gets:

```ruby
pbStartTrade(pbGet(1), :HAUNTER, "Spooky", "Ricky", 0, title: :DUSKMARK, scale: 0)
```

## Summary screen

The ribbons page shows ribbons and marks in a 3×3 grid sized for the icons in
`ribbons.png` (`PokemonSummary_Scene::RIBBON_*`). Until `bg_5.png` is redrawn
with matching slots, the slots are painted over it in code using its own
colours; set `RIBBON_DRAW_SLOTS = false` once the background has them. The
affixed ribbon has a small red flag.

On the page, press USE to choose ribbons. Selecting one shows its name, whether
it is a ribbon or a mark (and its rank), and its description. Press USE again
for **Set as title** / **Remove title**, **Move** (then choose where it goes)
and **Cancel**.

## Debug menu

- Pokémon > Cosmetic: **Set ribbons/marks**, **Set title**, **Set size**.
- Player options: **Set player birthday** (also clears it).

## Settings

All in `src/data/001_Settings.rb`:

| Setting | Default | Meaning |
| --- | --- | --- |
| `WILD_MARK_ODDS` | see above | 1 in N chance of each wild mark |
| `WILD_MARK_ROLLS` | 1 | wild mark rolls without the Mark Charm |
| `MARK_CHARM_EXTRA_ROLLS` | 2 | extra rolls with the Mark Charm |
| `GUARANTEED_WILD_SIZE_MARKS` | true | scale 0/255 wild Pokémon always have the Mini/Jumbo Mark |
| `AFFIX_WILD_MARK_TITLES` | true | wild Pokémon show their mark's title |
| `AUTO_AFFIX_TITLES` | false | a Pokémon without a title affixes the next titled ribbon/mark it gets |
| `PARTY_MARK_ODDS` | 50 | 1 in N chance of a party mark |
| `PARTNER_MARK_STEPS` | 1000 | steps between Partner Mark checks |
| `PARTNER_MARK_HAPPINESS` | 200 | happiness needed for the Partner Mark |
| `TITLE_TEXT_COLOR` | nil | a `<c2=...>` colour code for names with titles in battle, or nil |
| `NO_WILD_MARKS_SWITCH` | 38 | Game Switch that stops wild marks |

## Script reference

| Method | What it does |
| --- | --- |
| `pkmn.giveRibbon(id)` / `pkmn.giveMark(id)` | Gives a ribbon/mark |
| `pkmn.takeRibbon(id)` / `pkmn.takeMark(id)` | Takes it away (and its title, if affixed) |
| `pkmn.hasRibbon?(id)` / `pkmn.hasMark?(id)` | Whether it has one |
| `pkmn.marks`, `pkmn.numMarks` | Its marks |
| `pkmn.hasRibbonType?(filter)` | `:ribbon`, `:mark`, `:titled`, `:ranked` or a category (`:weather`, `:personality`, `:contest`…) |
| `pkmn.ribbonRank(id)` | The rank reached for a ranked ribbon |
| `pkmn.collapsed_ribbons` | Its ribbons without the lower ranks of ones it has |
| `pkmn.affixed_ribbon`, `pkmn.title`, `pkmn.name_with_title` | See [Titles](#titles) |
| `GameData::Ribbon.get(id).mark?`, `.title(pkmn)`, `.has_title?`, `.prefix_title?`, `.max_rank`, `.weather_mark?`… | Ribbon data |
| `pbRollWildMark(pkmn)`, `pbRollWildMarkID` | Roll a wild mark |
| `pbGiveMark(pkmn, id, affix = false)`, `pbGiveMarkToParty(id, odds, condition)` | Give marks |
| `pbMarksOfType(category)`, `pbGetPersonalityMark`, `pbGetTimeMark`, `pbGetWeatherMark` | Pick marks |
| `pbHasMarkCharm?` | Whether the player has the Mark Charm |
