# Hue variation

Like in Pokémon Stadium, every Pokémon's colors are slightly different from
the next one's. The difference comes from genes: each Pokémon carries two
**hue alleles**, passes one of them to each of its offspring, and shows a blend
of both. Its IVs add a small push on top. Each species has a hue range, so
Pokémon whose color is part of who they are only change a little (or not at
all).

The scripts are in `src/assets/plugins/[Iridescent Indigo] Graphics/`. All the
settings are in its `000_Settings.rb` (`GraphicsSettings`).

- [Genetics](#genetics)
- [Species ranges](#species-ranges)
- [Where it shows](#where-it-shows)
- [Settings](#settings)
- [Script reference](#script-reference)
- [Debug menu](#debug-menu)

## Genetics

- **Alleles.** Each allele is a number from -100 to 100. 0 means "normal
  colors". Alleles don't belong to a species, so a Pokémon keeps its color
  when it evolves, and color passes between species when breeding (e.g. with
  Ditto).
- **Wild, gift and traded-in Pokémon** get their alleles from their personal
  ID. They are worked out the first time they're needed, so a Pokémon's color
  never changes, and Pokémon from saves made before this feature get a color
  too. The personal ID is scrambled first, so color has nothing to do with
  gender, nature or ability. `HUE_ALLELE_SPREAD` makes extreme alleles rarer
  than subtle ones.
- **Blending.** Both alleles are shown: the Pokémon's **gene** is their
  average.
- **IVs.** The gene is pushed by up to `HUE_IV_INFLUENCE` (8 by default):
  perfect IVs push it up, all-zero IVs push it down and average IVs don't move
  it. Hyper Training doesn't change it.
- **Offspring.** A Day Care egg gets one random allele from each parent. Each
  of them has a `HUE_MUTATION_CHANCE`% chance (10%) of **drifting** by up to
  `HUE_MUTATION_SIZE` (24) either way, so new colors slowly appear in a line.
  Two parents with very different colors can have offspring with either
  parent's allele, or a blend.

## Species ranges

The gene (-100 to 100) is turned into degrees around the color wheel by the
species' **hue range**, `[most negative, most positive]`. A gene of 0 is always
the normal color, -100 reaches the first number and 100 the second.

```ruby
SPECIES_HUE_RANGES = {
  PIKACHU:   [-6, 6],     # Stays recognisably yellow
  MAGIKARP:  [-60, 60],   # Anything goes
  GYARADOS:  [-5, 30],    # Ranges don't need to be symmetric
  PIKACHU_1: [0, 0]       # This form never varies
}
```

- Species without an entry use `DEFAULT_HUE_RANGE` (`[-20, 20]`).
- A form's entry (`SPECIES_form`) is used instead of its species' entry.
- `[0, 0]` turns variation off.
- The first number can't be above 0 and the second can't be below 0, because 0
  is always the normal color.

## Where it shows

- Battle sprites (front and back), the summary screen and anywhere else that
  draws a Pokémon's sprite.
- Party icons (party screen, battle menus, etc.) and PC storage icons.
- The following Pokémon's overworld sprite.
- Shiny Pokémon vary too, starting from their shiny colors (turn off with
  `APPLY_TO_SHINY`).
- Eggs, and graphics of a species rather than a Pokémon (Pokédex, etc.), always
  have normal colors.

The colors are rotated on the graphics card when a graphic is loaded. One copy
is kept for each graphic and hue for as long as something shows it, and shifts
are rounded to `HUE_STEP` degrees so similar Pokémon share a copy. Animated
(GIF) sprites are recolored frame by frame. If a graphic can't be recolored, it
is shown with its normal colors and the problem is written to the console.

## Settings

All in `GraphicsSettings` (`000_Settings.rb`):

| Setting | Default | Meaning |
|---|---|---|
| `HUE_VARIATION_ENABLED` | `true` | Turns the whole feature on or off (alleles are kept either way) |
| `APPLY_TO_SHINY` | `true` | Whether shiny Pokémon vary |
| `DEFAULT_HUE_RANGE` | `[-20, 20]` | Hue range in degrees for species not in `SPECIES_HUE_RANGES` |
| `SPECIES_HUE_RANGES` | `{}` | Hue ranges per species or form |
| `HUE_IV_INFLUENCE` | `8` | Most the IVs push the gene, in allele units |
| `HUE_STEP` | `2` | Shifts are rounded to a multiple of this many degrees |
| `HUE_ALLELE_SPREAD` | `2` | Random draws averaged per wild allele (higher = fewer extreme colors) |
| `HUE_MUTATION_CHANCE` | `10` | Percent chance each inherited allele drifts |
| `HUE_MUTATION_SIZE` | `24` | Largest drift, in allele units |
| `RECOLOR_CACHE_SIZE` | `64` | Recolored graphics `RecolorCache` keeps when unused |

## Script reference

| Method | What it does |
|---|---|
| `pkmn.hue_alleles` | The two alleles, e.g. `[-12, 40]` |
| `pkmn.hue_alleles = [a, b]` | Sets them (clamped to -100..100); `nil` goes back to the personal ID's |
| `pkmn.hue_gene` | The blended gene with the IV push, -100 to 100 |
| `pkmn.hue_shift` | Degrees the Pokémon's graphics are rotated by, 0 to 359 |
| `pkmn.hue_varied?` | Whether it looks different from normal |
| `HueGenetics.inherit(mother, father)` | Alleles for a child of two Pokémon |
| `HueGenetics.range_for(species, form)` | A species' (or form's) hue range |
| `RecolorCache.load(path, ColorAdjust.new(hue))` | A hue-shifted copy of any graphic |

For example, a gift Pokémon with a special color:

```ruby
pkmn = Pokemon.new(:EEVEE, 5)
pkmn.hue_alleles = [100, 100]
pbAddPokemon(pkmn)
```

## Debug menu

In a Pokémon's debug menu, **Cosmetic info... → Set hue variation** shows its
alleles, gene, shift and species range. From there you can set either allele,
randomize both, or reset them to its personal ID's.
