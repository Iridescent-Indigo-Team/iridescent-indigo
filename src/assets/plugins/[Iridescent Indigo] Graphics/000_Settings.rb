#================================================================================================
# Pokémon Iridescent Indigo Graphics - 000_Settings.rb
#================================================================================================

#==================================================================
# module GraphicsSettings
#==================================================================
# @brief Central place for every tunable value used by the graphics plugin.
module GraphicsSettings
  #----------------------------------------------------------------
  # Hue variation (see docs/HUE_VARIATION.md)
  #----------------------------------------------------------------

  # @brief Master switch. When false every Pokémon is drawn with its normal colors
  # (its alleles are still kept and inherited).
  HUE_VARIATION_ENABLED = true

  # @brief Whether shiny Pokémon vary too (the shift is applied on top of the shiny palette).
  APPLY_TO_SHINY = true

  # @brief Hue range in degrees [most negative shift, most positive shift] used by species
  # without an entry in SPECIES_HUE_RANGES. A gene value of 0 is always the normal color;
  # -100 reaches the first number and +100 the second.
  DEFAULT_HUE_RANGE = [-20, 20]

  # @brief Per-species (or per-form) hue ranges, for Pokémon whose color is part of their
  # identity. Keys are species IDs, or "SPECIES_form" symbols for one form; a form entry
  # wins over its species' entry. [0, 0] turns variation off for that species/form.
  # Ranges don't need to be symmetric, e.g. [-5, 30].
  SPECIES_HUE_RANGES = {
    # PIKACHU:   [-6, 6],    # Stays recognisably yellow
    # CHARIZARD: [-10, 10],
    # MAGIKARP:  [-60, 60],  # Anything goes
    # PIKACHU_1: [0, 0]      # A form that never varies
  }

  # @brief How much an individual's IVs push its hue, in allele units (alleles are -100 to 100).
  # Perfect IVs push the gene by +this much, all-zero IVs by -this much.
  HUE_IV_INFLUENCE = 8

  # @brief Hue shifts are rounded to a multiple of this many degrees, so Pokémon with almost
  # the same color share one recolored graphic. 1 disables rounding.
  HUE_STEP = 2

  # @brief How many random draws are averaged for each allele of a wild/gift Pokémon. 1 gives
  # an even spread; higher values make extreme colors rarer.
  HUE_ALLELE_SPREAD = 2

  # @brief Chance (in percent) that each allele an offspring inherits drifts a little.
  HUE_MUTATION_CHANCE = 10

  # @brief Largest drift of a mutated allele, in allele units (alleles are -100 to 100).
  HUE_MUTATION_SIZE = 24

  #----------------------------------------------------------------
  # Saturation and brightness variation
  #----------------------------------------------------------------

  # @brief Saturation range in percent [most negative, most positive] for species without
  # an entry in SPECIES_SATURATION_RANGES. Works like DEFAULT_HUE_RANGE. Kept smaller on
  # the positive side, because vivid colors are harder on the eyes than muted ones.
  DEFAULT_SATURATION_RANGE = [-15, 10]

  # @brief Brightness range in percent [most negative, most positive] for species without
  # an entry in SPECIES_BRIGHTNESS_RANGES. Kept smaller on the positive side for players
  # sensitive to bright light.
  DEFAULT_BRIGHTNESS_RANGE = [-10, 8]

  # @brief Per-species/form saturation ranges, keyed like SPECIES_HUE_RANGES.
  SPECIES_SATURATION_RANGES = {}

  # @brief Per-species/form brightness ranges, keyed like SPECIES_HUE_RANGES.
  SPECIES_BRIGHTNESS_RANGES = {}

  # @brief Saturation changes are rounded to a multiple of this many percent.
  SATURATION_STEP = 2

  # @brief Brightness changes are rounded to a multiple of this many percent.
  BRIGHTNESS_STEP = 2

  #----------------------------------------------------------------
  # Comfort limits (accessibility)
  #----------------------------------------------------------------
  # Variation never pushes a color past these limits. A color that was already past a
  # limit in the original art is never pushed further out, but is left as drawn.

  # @brief Highest saturation (0.0-1.0) variation can raise a color to.
  COMFORT_MAX_SATURATION = 0.85

  # @brief Highest brightness (0.0-1.0) variation can raise a color to.
  COMFORT_MAX_BRIGHTNESS = 0.92

  # @brief Lowest brightness (0.0-1.0) variation can lower a color to, so dark Pokémon
  # don't disappear into their outlines.
  COMFORT_MIN_BRIGHTNESS = 0.18

  # @brief Colors darker than this (0.0-1.0) are outlines and are never changed, so the
  # shape of a Pokémon stays as readable as in the original art.
  OUTLINE_BRIGHTNESS = 0.16

  #----------------------------------------------------------------
  # Player option
  #----------------------------------------------------------------

  # @brief The "Color variation" option's value in a new game: 0 = Full,
  # 1 = Hue only, 2 = Off.
  DEFAULT_PLAYER_SETTING = 0

  # @brief Most recolored graphics RecolorCache keeps once nothing else uses them.
  RECOLOR_CACHE_SIZE = 64
end
