# Hue variation

Like in Pokémon Stadium, every Pokémon's colors are slightly different from
the next one's. The difference comes from genes: each Pokémon has three color
genes (**hue**, **saturation** and **brightness**) with two alleles each. It
passes one allele of each gene to each of its offspring, and shows a blend of
both. Its IVs add a small push to its hue. Each species has a range for each
gene, so Pokémon whose color is part of who they are only change a little (or
not at all).

Saturation and brightness change much less than hue, and **comfort limits**
stop any color from becoming harshly vivid, glaringly bright or too dark to
read. Players can turn the variation down or off in the Options menu.

The scripts are in `src/assets/plugins/[Iridescent Indigo] Graphics/`. All the
settings are in its `000_Settings.rb` (`GraphicsSettings`).

- [Genetics](#genetics)
- [Species ranges](#species-ranges)
- [Saturation and brightness](#saturation-and-brightness)
- [Comfort limits](#comfort-limits)
- [Player option](#player-option)
- [Where it shows](#where-it-shows)
- [Settings](#settings)
- [Script reference](#script-reference)
- [Debug menu](#debug-menu)

## Genetics

- **Alleles.** Each allele is a number from -100 to 100. 0 means "normal
  colors". The three genes are separate: a Pokémon can have a shifted hue but
  normal brightness. Alleles don't belong to a species, so a Pokémon keeps its color
  when it evolves, and color passes between species when breeding (e.g. with
  Ditto).
- **Wild, gift and traded-in Pokémon** get their alleles from their personal
  ID. They are worked out the first time they're needed, so a Pokémon's color
  never changes, and Pokémon from saves made before this feature get a color
  too. The personal ID is scrambled first (differently for each gene), so color has nothing to do with
  gender, nature or ability. `HUE_ALLELE_SPREAD` makes extreme alleles rarer
  than subtle ones.
- **Blending.** Both alleles are shown: the Pokémon's **gene** is their
  average.
- **IVs.** The hue gene is pushed by up to `HUE_IV_INFLUENCE` (8 by default):
  perfect IVs push it up, all-zero IVs push it down and average IVs don't move
  it. Hyper Training doesn't change it. IVs don't affect saturation or
  brightness, so strong Pokémon aren't always the brightest.
- **Offspring.** For each gene, a Day Care egg gets one random allele from
  each parent. Each
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

## Saturation and brightness

These work exactly like hue, but their ranges are in percent and much smaller:

| Gene | Default range | Species ranges |
|---|---|---|
| Saturation | `[-15, 10]` | `SPECIES_SATURATION_RANGES` |
| Brightness | `[-10, 8]` | `SPECIES_BRIGHTNESS_RANGES` |

The positive side is smaller on purpose: more vivid or brighter colors are
harder on the eyes than muted or darker ones. A change of +10% moves a color
10% of the way toward full saturation (or brightness), and -10% takes away 10%
of what it has, so a change never overshoots and clips.

```ruby
SPECIES_SATURATION_RANGES = {
  PIKACHU: [0, 0]        # Pikachu's yellow is never dulled or intensified
}
SPECIES_BRIGHTNESS_RANGES = {
  UMBREON: [-4, 8]       # Already dark, so it can barely get darker
}
```

## Comfort limits

To keep sprites comfortable to look at for light-sensitive players, and readable
for color-blind players, every recolored color is checked:

- **Outlines are never touched.** Colors darker than `OUTLINE_BRIGHTNESS` are
  left exactly as drawn, so a Pokémon's shape is as clear as in the original.
- **Not too vivid.** Variation never raises saturation above
  `COMFORT_MAX_SATURATION` (85%).
- **Not too bright.** Variation never raises brightness above
  `COMFORT_MAX_BRIGHTNESS` (92%).
- **Not too dark.** Variation never lowers brightness below
  `COMFORT_MIN_BRIGHTNESS` (18%), so dark Pokémon don't vanish into their
  outlines.

A color that the original art already has past a limit (e.g. a pure white
highlight) is left as drawn. The limits only stop variation from pushing colors
further.

## Player option

**Options → Color Variation**:

| Choice | Effect |
|---|---|
| Full | Hue, saturation and brightness all vary (default) |
| Hue Only | Only hue varies; saturation and brightness stay as drawn |
| Off | Every Pokémon has its normal colors |

The choice only changes how Pokémon are drawn. Their genes are kept and still
passed on. `DEFAULT_PLAYER_SETTING` sets the choice for new games.

## Where it shows

- Battle sprites (front and back), the summary screen and anywhere else that
  draws a Pokémon's sprite.
- Party icons (party screen, battle menus, etc.) and PC storage icons.
- The following Pokémon's overworld sprite.
- Shiny Pokémon vary too, starting from their shiny colors (turn off with
  `APPLY_TO_SHINY`).
- Eggs, and graphics of a species rather than a Pokémon (Pokédex, etc.), always
  have normal colors.

Hue-only changes are made on the graphics card when a graphic is loaded.
Saturation and brightness changes are made once per distinct color of the
graphic, which is quick for pixel art. One copy is kept for each graphic and
set of changes for as long as something shows it, and changes are rounded to
`HUE_STEP`, `SATURATION_STEP` and `BRIGHTNESS_STEP` so similar Pokémon share a
copy. Animated (GIF) sprites are recolored frame by frame. If a graphic can't be recolored, it
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
| `HUE_ALLELE_SPREAD` | `2` | Random draws averaged per wild allele, all genes (higher = fewer extreme colors) |
| `HUE_MUTATION_CHANCE` | `10` | Percent chance each inherited allele drifts |
| `HUE_MUTATION_SIZE` | `24` | Largest drift, in allele units (all genes) |
| `DEFAULT_SATURATION_RANGE` | `[-15, 10]` | Saturation range in percent for species not in `SPECIES_SATURATION_RANGES` |
| `DEFAULT_BRIGHTNESS_RANGE` | `[-10, 8]` | Brightness range in percent for species not in `SPECIES_BRIGHTNESS_RANGES` |
| `SPECIES_SATURATION_RANGES` | `{}` | Saturation ranges per species or form |
| `SPECIES_BRIGHTNESS_RANGES` | `{}` | Brightness ranges per species or form |
| `SATURATION_STEP` | `2` | Saturation changes are rounded to a multiple of this |
| `BRIGHTNESS_STEP` | `2` | Brightness changes are rounded to a multiple of this |
| `COMFORT_MAX_SATURATION` | `0.85` | Highest saturation variation can raise a color to |
| `COMFORT_MAX_BRIGHTNESS` | `0.92` | Highest brightness variation can raise a color to |
| `COMFORT_MIN_BRIGHTNESS` | `0.18` | Lowest brightness variation can lower a color to |
| `OUTLINE_BRIGHTNESS` | `0.16` | Colors darker than this are outlines and never change |
| `DEFAULT_PLAYER_SETTING` | `0` | Color Variation option for new games (0 Full, 1 Hue Only, 2 Off) |
| `RECOLOR_CACHE_SIZE` | `64` | Recolored graphics `RecolorCache` keeps when unused |

## Script reference

| Method | What it does |
|---|---|
| `pkmn.hue_alleles` | The two hue alleles, e.g. `[-12, 40]` |
| `pkmn.hue_alleles = [a, b]` | Sets them (clamped to -100..100); `nil` goes back to the personal ID's |
| `pkmn.saturation_alleles`, `pkmn.brightness_alleles` | The same for the other genes (also settable) |
| `pkmn.color_alleles(trait)`, `pkmn.set_color_alleles(trait, value)` | The same, with the gene as `:hue`, `:saturation` or `:brightness` |
| `pkmn.hue_gene`, `pkmn.saturation_gene`, `pkmn.brightness_gene` | The blended genes (hue includes the IV push), -100 to 100 |
| `pkmn.hue_shift` | Degrees the Pokémon's graphics are rotated by, 0 to 359 |
| `pkmn.color_adjust` | Every change it's drawn with, as a `ColorAdjust` (hue, saturation, value) |
| `pkmn.hue_varied?` | Whether it looks different from normal |
| `HueGenetics.inherit(mother, father, trait)` | Alleles for a child of two Pokémon |
| `HueGenetics.range_for(species, form, trait)` | A species' (or form's) range for a gene |
| `$PokemonSystem.color_variation` | The player's option (0 Full, 1 Hue Only, 2 Off) |
| `RecolorCache.load(path, ColorAdjust.new(hue, sat, value))` | A recolored copy of any graphic |

For example, a gift Pokémon with a special color:

```ruby
pkmn = Pokemon.new(:EEVEE, 5)
pkmn.hue_alleles = [100, 100]
pkmn.brightness_alleles = [-60, -60]
pbAddPokemon(pkmn)
```

## Debug menu

In a Pokémon's debug menu, **Cosmetic info... → Set color variation** lets you
pick a gene (hue, saturation or brightness), then shows its alleles, gene,
change and species range. From there you can set either allele, randomize both,
or reset them to its personal ID's.
