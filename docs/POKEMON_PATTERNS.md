# Pokémon patterns

Some Pokémon have a **pattern**: an alternate look, such as spots or stripes,
drawn with whole sprites of its own. Patterns are defined per **evolution
line**, so a spotted Bulbasaur becomes a spotted Ivysaur. A Pokémon gets its
pattern the first time it's needed, the same way a form is worked out. It passes
its pattern on to its offspring, and it keeps it when it's traded or evolves.

Patterns are a cosmetic layer of their own. They never change a Pokémon's
form, and they are drawn on top of its form, gender, shininess and
[color variation](HUE_VARIATION.md).

The scripts are in
`src/assets/plugins/[Iridescent Indigo] Graphics/Pokemon Patterns/`, and the
settings are in that plugin's `000_Settings.rb` (`GraphicsSettings`).

- [Defining patterns](#defining-patterns)
- [Sprites](#sprites)
- [Rolling a pattern](#rolling-a-pattern)
- [Breeding](#breeding)
- [Where it shows](#where-it-shows)
- [Pokédex](#pokédex)
- [Trainers' Pokémon](#trainers-pokémon)
- [Events](#events)
- [Debug menu](#debug-menu)
- [Settings](#settings)
- [Script reference](#script-reference)

## Defining patterns

Patterns are defined in `pokemon_patterns.txt`. Its source is the JSON in
`src/pbs/pokemon_patterns/`, with one file per line (see
[PBS_JSON.md](PBS_JSON.md)). Each section is one evolution line, named after
the line's **first species**: its baby species, ignoring incense. For example,
use `[AZURILL]` for Marill and Azumarill.

```
[BULBASAUR]
NoPatternWeight = 80
NoPatternDominance = 2
Pattern = SPOTTED,Spotted,15,1
Pattern = STRIPED,Striped,5,3
```

```json
{
  "$schema": "../_schema/pokemon_patterns.entry.schema.json",
  "id": "BULBASAUR",
  "no_pattern_weight": 80,
  "no_pattern_dominance": 2,
  "patterns": [
    {"id": "SPOTTED", "real_name": "Spotted", "weight": 15, "dominance": 1},
    {"id": "STRIPED", "real_name": "Striped", "weight": 5, "dominance": 3}
  ]
}
```

| Key | JSON | Meaning |
|---|---|---|
| `Pattern = ID,Name,Weight[,Dominance]` | `patterns` | One line per pattern. `ID` is a symbol used in scripts, PBS files and sprite folders. `Name` is shown to the player and can be translated. `Weight` (above 0) is its chance when rolled. `Dominance` is how strongly it's passed on (default `DEFAULT_PATTERN_DOMINANCE`). |
| `NoPatternWeight` | `no_pattern_weight` | The chance of having **no pattern** when rolled (default `DEFAULT_NO_PATTERN_WEIGHT`, 0) |
| `NoPatternDominance` | `no_pattern_dominance` | How strongly "no pattern" is passed on when breeding (default `DEFAULT_PATTERN_DOMINANCE`) |

- Pattern ids belong to their line, so two lines can both have `SPOTTED`.
- `NONE` is reserved. It means "no pattern" and can't be a pattern id.
- Weights are relative. With the example, 80% of Bulbasaur have no pattern,
  15% are spotted and 5% are striped.

`make validate-pbs` and the game's compiler both check these rules:

- The section is the first species of its line.
- Pattern ids are unique within a line.
- `NONE` isn't used as a pattern id.
- Weights are above 0.

The file is optional. Without it, no Pokémon has a pattern.

`src/pbs/pokemon_patterns/bulbasaur.json` is an example. It has no sprites yet,
so its Pokémon are drawn normally (see below).

## Sprites

A pattern's sprites are **whole sprites**, not overlays. They live in a folder
per pattern id that mirrors the normal sprite folders:

```
Graphics/Pokemon/Patterns/SPOTTED/Front/BULBASAUR.png
Graphics/Pokemon/Patterns/SPOTTED/Front shiny/BULBASAUR.png
Graphics/Pokemon/Patterns/SPOTTED/Back/BULBASAUR.png
Graphics/Pokemon/Patterns/SPOTTED/Back shiny/BULBASAUR.png
Graphics/Pokemon/Patterns/SPOTTED/Icons/BULBASAUR.png
Graphics/Pokemon/Patterns/SPOTTED/Icons shiny/BULBASAUR.png
Graphics/Characters/Patterns/SPOTTED/Followers/BULBASAUR.png
Graphics/Characters/Patterns/SPOTTED/Followers shiny/BULBASAUR.png
```

In this repository they go in `src/assets/graphics/` at 1× scale, like every
other graphic (see [BUILDING.md](BUILDING.md)). Files are named like normal
sprites: `SPECIES`, `SPECIES_form`, `SPECIES_female`, `SPECIES_shadow`.

How a sprite is found:

- **Shininess must match.** A shiny Pokémon uses the pattern's `... shiny`
  folder. If that sprite doesn't exist, it uses the normal **shiny** sprite, not
  the non-shiny pattern sprite.
- **The form must match.** For example, `VULPIX_1` uses
  `Patterns/SPOTTED/Front/VULPIX_1.png`. If a form has no sprite of its own in
  the normal folders (it looks like form 0), its pattern sprite can be form 0's
  too.
- **Gender and shadow fall back** the way normal sprites do. A female uses
  `SPECIES_female` if there is one, otherwise `SPECIES`.
- **Anything missing falls back quietly** to the normal sprite. So does a
  pattern that the Pokémon's line doesn't have, and an egg. You can define a
  pattern before its art exists, or draw only some of a line's species.

Color variation is applied to whichever sprite is chosen.

Results are cached. After adding sprites while the game is running, call
`PatternSprites.clear_cache`.

## Rolling a pattern

`pkmn.pattern` is a symbol:

| Value | Meaning |
|---|---|
| `nil` | Not rolled yet, or its line has no patterns |
| `:NONE` | Rolled: no pattern (normal sprites) |
| `:SPOTTED` etc. | One of its line's patterns |

- A Pokémon of a line with patterns rolls one the first time
  `pkmn.pattern` is read, for example when its sprite is first drawn. The roll
  uses the line's weights, and the result is kept.
- Wild, gift and traded-in Pokémon, and Pokémon from saves made before patterns
  existed, all roll this way.
- A Pokémon of a line without patterns stays unrolled. If its line is given
  patterns later, even in an update, it rolls one then.
- Evolving keeps the pattern, since the whole line shares the same patterns.
- A pattern that the Pokémon's current line doesn't have is kept but not shown,
  for example after changing its species in the debug menu.

## Breeding

A Day Care egg's pattern comes from its parents:

1. **Only parents of the egg's line count.** A parent can pass on its pattern
   only if the egg's line has that pattern ("no pattern" counts). Ditto, or a
   parent of another line, passes nothing on.
2. **Everstone.** A parent holding an Everstone always passes its pattern on,
   with no chance of mutation (`PATTERN_EVERSTONE_LOCK`). If both parents hold
   one, either one's is picked.
3. **Mutation.** Otherwise, there's a `PATTERN_MUTATION_CHANCE`% chance (5%)
   that the egg rolls a fresh pattern from its line's weights, as if it were
   wild. It always rolls a fresh one if no parent can pass a pattern on.
4. **Dominance.** Otherwise, one parent's pattern is passed on, with odds in
   proportion to each pattern's dominance. For example, a striped parent
   (dominance 3) and an unpatterned one (`NoPatternDominance` 2) give striped
   offspring 3 times in 5. If both patterns have dominance 0, the odds are
   equal.

## Where it shows

- Battle sprites (front and back), the summary screen, the evolution scene,
  trading, the Hall of Fame and anywhere else that draws a Pokémon's sprite.
- Party icons, battle menus and PC storage icons.
- The following Pokémon. The follower refreshes when its pattern changes.
- **Transform and Imposter.** The user is drawn with the target's own pattern.
  The scene is given the target Pokémon itself (as it is for color variation),
  so this needs no special code.
- **Illusion.** A Pokémon under Illusion is sent out as the Pokémon it
  disguises as, so that Pokémon's pattern is shown until the Illusion breaks.
  The Pokédex records the disguise's pattern, the same way it records the
  disguise's species.
- Eggs always look normal.

## Pokédex

The Pokédex records each species' seen patterns, and the forms they were seen
in. A pattern is recorded when the player sees it in battle, catches it, gets
it as a gift or in a trade, hatches it or evolves it, which is everywhere a
form is recorded.

Seen patterns are listed on the existing **Forms page**, each after the form it
was seen in (e.g. "Spotted", or "Spotted (Alolan Form)"). Choosing one shows its
sprites and icon on the entry, using the same quiet fallback. With
`Settings::DEX_SHOWS_ALL_FORMS`, every pattern is listed. A newly caught
Pokémon's entry shows its pattern. No new graphics are needed.

## Trainers' Pokémon

A trainer's Pokémon can be given a pattern:

```
[YOUNGSTER,Ben]
Pokemon = IVYSAUR,14
    Pattern = STRIPED
```

```json
"pokemon": [{"species": "IVYSAUR", "level": 14, "pattern": "STRIPED"}]
```

- `NONE` gives it no pattern.
- The pattern must exist in the species' line. `make validate-pbs` and the
  compiler both check this.
- A Pokémon without `Pattern` rolls one, seeded from the trainer's type, name
  and party slot (like its colors), so it looks the same in every battle and
  rematch.
- The Debug menu's trainer editor keeps a Pokémon's pattern but can't change
  it. Edit the JSON (or PBS) instead.

## Events

```ruby
pbAddPokemonWithPattern(:BULBASAUR, 5, :SPOTTED)   # A gift Pokémon with a pattern
pbSetNextWildPattern(:STRIPED)                     # The next wild Pokémon has this pattern
```

- `pbSetNextWildPattern` applies to the next wild Pokémon only (the first one
  in a double battle). `nil` clears it.
- A pattern that the Pokémon's line doesn't have is ignored, and the Pokémon
  rolls one as usual.
- To give a Pokémon a pattern any other way, set `pkmn.pattern = :SPOTTED`
  before adding it.

## Debug menu

In a Pokémon's debug menu, **Cosmetic info... → Set pattern** shows its
current pattern. It also warns when that pattern has no sprite for this
Pokémon, so the normal sprite is shown. The options are:

- Each of its line's patterns (the current one is marked `*`)
- **No pattern**
- **Re-roll**: a new roll from the line's weights
- **Clear**: back to "not rolled", so it rolls again when next needed

## Settings

All in `GraphicsSettings` (`000_Settings.rb`):

| Setting | Default | Meaning |
|---|---|---|
| `PATTERNS_ENABLED` | `true` | Whether patterns are drawn. Patterns are kept, inherited and recorded either way. |
| `DEFAULT_NO_PATTERN_WEIGHT` | `0` | `NoPatternWeight` for lines that don't set it. 0 means they always roll a pattern. |
| `DEFAULT_PATTERN_DOMINANCE` | `1` | Dominance of patterns (and of "no pattern") that don't set one |
| `PATTERN_MUTATION_CHANCE` | `5` | Percent chance that an egg rolls a fresh pattern |
| `PATTERN_EVERSTONE_LOCK` | `true` | Whether an Everstone holder always passes its pattern on |

## Script reference

| Method | What it does |
|---|---|
| `pkmn.pattern` | Its pattern (rolled now if needed), `:NONE`, or `nil` if its line has none |
| `pkmn.pattern = :SPOTTED` | Sets it (`:NONE` for none, `nil` to roll again when next needed) |
| `pkmn.pattern_simple` | The stored pattern, without rolling one |
| `pkmn.patterned?` | Whether it has one of its line's patterns |
| `pkmn.pattern_name` | Its pattern's name ("No pattern" if none) |
| `PatternData.roll(species)` | A random pattern from a line's weights |
| `PatternData.ids_for(species)` | A line's pattern ids |
| `PatternData.valid?(species, pattern)` | Whether a pattern (or `:NONE`) belongs to a species' line |
| `PatternData.name_for(species, pattern)` | A pattern's name |
| `PatternData.shown_pattern(pkmn)` | The pattern it's drawn with, or `nil` |
| `PatternData.inherit(egg, mother, father)` | The pattern an egg inherits |
| `PatternSprites.resolve(root, subfolder, species, form, gender, shiny, shadow, pattern)` | A pattern sprite's file, or `nil` |
| `$player.pokedex.seen_pattern?(species, pattern[, form])` | Whether a pattern has been seen |
| `$player.pokedex.seen_patterns(species)` | The patterns seen of a species |
| `GameData::PokemonPattern.get(:BULBASAUR)` | A line's data |

The sprite hooks are `GameData::Species.sprite_filename_from_pokemon` (front
and back sprites, defined by the color variation's `009_Sprites.rb`),
`GameData::Species.icon_filename_from_pokemon` and
`FollowingPokemon.sprite_name`.
