#================================================================================================
# Pokémon Iridescent Indigo Graphics/Pokemon Hue Variation - 007_Generation.rb
#================================================================================================

#==================================================================
# module HueGenetics
#==================================================================
# @brief The genetics behind each Pokémon's color variation.
# Every Pokémon carries three genes, one per trait (hue, saturation and brightness), and
# two alleles for each, from ALLELE_MIN to ALLELE_MAX. Alleles don't depend on species:
# 0 means "normal colors" and the species' range for that trait decides how much the
# extremes are worth. Both alleles are expressed (they blend), and for hue only, the
# Pokémon's IVs add a small push on top:
#
#   gene   = average(allele 1, allele 2) [+ IV push for hue]   (-100 to 100)
#   amount = gene scaled onto the species' [min, max] range     (degrees or percent)
#
# Wild and gift Pokémon get alleles derived from their personal ID, so a Pokémon's colors
# never change and Pokémon from older saves get them too. Offspring inherit one allele per
# trait from each parent instead (see 008_Inheritance.rb).
module HueGenetics
  # Lowest allele value
  ALLELE_MIN = -100
  # Highest allele value
  ALLELE_MAX = 100
  # Salt mixed into the personal ID for hue alleles, so they don't correlate with
  # gender/nature/ability. Must never change, or every existing Pokémon changes color.
  PERSONAL_ID_SALT = 0x48554531   # "HUE1"

  # @brief Each trait: its personal ID salt, the Pokémon instance variable holding its
  # alleles, and the GraphicsSettings names of its default range, species ranges and step.
  TRAITS = {
    hue:        {salt: PERSONAL_ID_SALT, ivar: :@hue_alleles,
                  default: :DEFAULT_HUE_RANGE, species: :SPECIES_HUE_RANGES, step: :HUE_STEP},
    saturation: {salt: 0x53415431, ivar: :@saturation_alleles,   # "SAT1"
                  default: :DEFAULT_SATURATION_RANGE, species: :SPECIES_SATURATION_RANGES,
                  step: :SATURATION_STEP},
    brightness: {salt: 0x42524931, ivar: :@brightness_alleles,   # "BRI1"
                  default: :DEFAULT_BRIGHTNESS_RANGE, species: :SPECIES_BRIGHTNESS_RANGES,
                  step: :BRIGHTNESS_STEP}
  }.freeze

  # @brief Values of the player's "Color variation" option.
  PLAYER_FULL     = 0
  PLAYER_HUE_ONLY = 1
  PLAYER_OFF      = 2

  module_function

  #----------------------------------------------------------------
  # Alleles
  #----------------------------------------------------------------

  # @brief Clamps a value to the allele range.
  # @param value [Numeric]
  # @return [Integer]
  def clamp_allele(value)
    return value.round.clamp(ALLELE_MIN, ALLELE_MAX)
  end

  # @brief Normalizes a pair of alleles (clamped integers, always two of them).
  # @param alleles [Array<Numeric>, Numeric]
  # @return [Array<Integer>]
  def normalize(alleles)
    alleles = Array(alleles)
    alleles = [0, 0] if alleles.empty?
    alleles = [alleles[0], alleles[0]] if alleles.length == 1
    return [clamp_allele(alleles[0]), clamp_allele(alleles[1])]
  end

  # @brief Looks up a trait's definition.
  # @param trait [Symbol] :hue, :saturation or :brightness.
  # @return [Hash]
  def trait_info(trait)
    return TRAITS[trait] || raise(ArgumentError, "unknown color trait: #{trait.inspect}")
  end

  # @brief Reads a value from GraphicsSettings by name.
  # @param name [Symbol]
  # @return [Object]
  def setting(name)
    return GraphicsSettings.const_get(name)
  end

  # @brief Scrambles a 32-bit integer (MurmurHash3 finalizer). Nearby inputs give unrelated
  # outputs, so neighbouring personal IDs don't get similar colors.
  # @param value [Integer]
  # @return [Integer] 0 to 2**32 - 1.
  def mix32(value)
    x = value & 0xFFFFFFFF
    x ^= x >> 16
    x = (x * 0x85EBCA6B) & 0xFFFFFFFF
    x ^= x >> 13
    x = (x * 0xC2B2AE35) & 0xFFFFFFFF
    x ^= x >> 16
    return x
  end

  # @brief Converts a byte (0-255) to an allele value.
  # @param byte [Integer]
  # @return [Integer]
  def byte_to_allele(byte)
    return ALLELE_MIN + ((byte & 0xFF) * (ALLELE_MAX - ALLELE_MIN) / 255.0).round
  end

  # @brief The alleles a Pokémon with this personal ID is born with when it has no parents.
  # Each allele averages GraphicsSettings::HUE_ALLELE_SPREAD pseudo-random draws, so with a
  # spread above 1 extreme colors are rarer than subtle ones. Each trait uses its own salt,
  # so the three genes are independent.
  # @param personal_id [Integer]
  # @param trait [Symbol] :hue, :saturation or :brightness.
  # @return [Array<Integer>] Two alleles.
  def alleles_from_personal_id(personal_id, trait = :hue)
    spread = [GraphicsSettings::HUE_ALLELE_SPREAD.to_i, 1].max
    state = mix32((personal_id || 0) ^ trait_info(trait)[:salt])
    return Array.new(2) do
      total = 0
      spread.times do
        state = mix32(state + 0x9E3779B9)
        total += byte_to_allele(state >> 24)
      end
      next clamp_allele(total.to_f / spread)
    end
  end

  # @brief A random allele, distributed like personal ID alleles.
  # @return [Integer]
  def random_allele
    return alleles_from_personal_id(rand(2**32))[0]
  end

  #----------------------------------------------------------------
  # Phenotype
  #----------------------------------------------------------------

  # @brief How much a Pokémon's IVs push its hue gene, from -HUE_IV_INFLUENCE (all IVs 0) to
  # +HUE_IV_INFLUENCE (all IVs perfect). Uses its real IVs, so Hyper Training doesn't change it.
  # @param pkmn [Pokemon]
  # @return [Float]
  def iv_push(pkmn)
    influence = GraphicsSettings::HUE_IV_INFLUENCE
    return 0.0 if !influence || influence == 0 || !pkmn.iv
    total = 0
    count = 0
    GameData::Stat.each_main do |s|
      total += pkmn.iv[s.id] || 0
      count += 1
    end
    return 0.0 if count == 0
    fraction = total.to_f / (count * Pokemon::IV_STAT_LIMIT)   # 0.0 to 1.0
    return (fraction - 0.5) * 2 * influence
  end

  # @brief The expressed gene for a trait: both alleles blended, plus the IV push for hue.
  # @param pkmn [Pokemon]
  # @param trait [Symbol] :hue, :saturation or :brightness.
  # @return [Float] ALLELE_MIN to ALLELE_MAX.
  def gene_for(pkmn, trait = :hue)
    a, b = pkmn.color_alleles(trait)
    gene = (a + b) / 2.0
    gene += iv_push(pkmn) if trait == :hue
    return gene.clamp(ALLELE_MIN.to_f, ALLELE_MAX.to_f)
  end

  # @brief A species' (or form's) range for a trait.
  # @param species [Symbol]
  # @param form [Integer]
  # @param trait [Symbol] :hue (degrees), :saturation or :brightness (percent).
  # @return [Array<Integer>] [most negative change, most positive change]
  def range_for(species, form = 0, trait = :hue)
    info = trait_info(trait)
    ranges = setting(info[:species])
    species_id = GameData::Species.try_get(species)&.species || species
    ret = ranges[:"#{species_id}_#{form}"] if form && form > 0
    ret ||= ranges[species_id]
    ret ||= setting(info[:default])
    return [[ret[0].to_i, 0].min, [ret[1].to_i, 0].max]
  end

  # @brief Scales a gene onto a range: 0 is no change, ALLELE_MIN is range[0] and
  # ALLELE_MAX is range[1].
  # @param gene [Numeric]
  # @param range [Array<Integer>]
  # @return [Float]
  def gene_to_degrees(gene, range)
    return (gene < 0) ? gene / -ALLELE_MIN.to_f * -range[0] : gene / ALLELE_MAX.to_f * range[1]
  end

  # @brief The player's "Color variation" option.
  # @return [Integer] PLAYER_FULL, PLAYER_HUE_ONLY or PLAYER_OFF.
  def player_setting
    system = (defined?($PokemonSystem)) ? $PokemonSystem : nil
    return system.color_variation if system.respond_to?(:color_variation)
    return GraphicsSettings::DEFAULT_PLAYER_SETTING
  end

  # @brief Whether a Pokémon is drawn with color variation at all.
  # @param pkmn [Pokemon]
  # @return [Boolean]
  def varies?(pkmn)
    return false if !GraphicsSettings::HUE_VARIATION_ENABLED
    return false if player_setting == PLAYER_OFF
    return false if !pkmn || pkmn.egg?
    return false if pkmn.shiny? && !GraphicsSettings::APPLY_TO_SHINY
    return true
  end

  # @brief Whether a trait is shown, given the developer settings and the player's option.
  # @param pkmn [Pokemon]
  # @param trait [Symbol]
  # @return [Boolean]
  def shows?(pkmn, trait)
    return false if !varies?(pkmn)
    return trait == :hue || player_setting == PLAYER_FULL
  end

  # @brief How much a trait changes a Pokémon's graphics, rounded to the trait's step.
  # @param pkmn [Pokemon]
  # @param trait [Symbol]
  # @return [Integer] Signed degrees for hue, signed percent for saturation/brightness.
  def amount_for(pkmn, trait)
    return 0 if !shows?(pkmn, trait)
    range = range_for(pkmn.species, pkmn.form, trait)
    amount = gene_to_degrees(gene_for(pkmn, trait), range)
    step = [setting(trait_info(trait)[:step]).to_i, 1].max
    return (step * (amount / step).round).to_i.clamp(range[0], range[1])   # Rounding never leaves the range
  end

  # @brief The hue rotation a Pokémon's graphics are drawn with.
  # @param pkmn [Pokemon]
  # @return [Integer] 0 to 359 (0 = normal colors).
  def degrees_for(pkmn)
    return amount_for(pkmn, :hue) % 360
  end

  # @brief The hue shift as a signed number of degrees (-180 to 179), for display.
  # @param pkmn [Pokemon]
  # @return [Integer]
  def signed_degrees_for(pkmn)
    degrees = degrees_for(pkmn)
    return (degrees >= 180) ? degrees - 360 : degrees
  end

  # @brief Every change a Pokémon's graphics are drawn with.
  # @param pkmn [Pokemon]
  # @return [ColorAdjust]
  def color_adjust_for(pkmn)
    return ColorAdjust.new(degrees_for(pkmn), amount_for(pkmn, :saturation), amount_for(pkmn, :brightness))
  end
end

#==================================================================
# class Pokemon
#==================================================================
# @brief Color alleles and the color changes they produce.
class Pokemon
  # @brief This Pokémon's two alleles for a trait. Pokémon without stored alleles (wild
  # Pokémon, gifts, Pokémon from older saves) get them from their personal ID the first
  # time they're asked for.
  # @param trait [Symbol] :hue, :saturation or :brightness.
  # @return [Array<Integer>] Two values from HueGenetics::ALLELE_MIN to ALLELE_MAX.
  def color_alleles(trait)
    ivar = HueGenetics.trait_info(trait)[:ivar]
    value = instance_variable_get(ivar)
    if !value
      value = HueGenetics.alleles_from_personal_id(@personalID, trait)
      instance_variable_set(ivar, value)
    end
    return value
  end

  # @brief Sets both alleles for a trait.
  # @param trait [Symbol] :hue, :saturation or :brightness.
  # @param value [Array<Integer>, nil] Two alleles; nil derives them from the personal ID again.
  def set_color_alleles(trait, value)
    instance_variable_set(HueGenetics.trait_info(trait)[:ivar], (value.nil?) ? nil : HueGenetics.normalize(value))
  end

  # @return [Array<Integer>] The two hue alleles.
  def hue_alleles; return color_alleles(:hue); end

  # @param value [Array<Integer>, nil] Two hue alleles; nil derives them from the personal ID.
  def hue_alleles=(value); set_color_alleles(:hue, value); end

  # @return [Array<Integer>] The two saturation alleles.
  def saturation_alleles; return color_alleles(:saturation); end

  # @param value [Array<Integer>, nil] Two saturation alleles; nil derives them from the personal ID.
  def saturation_alleles=(value); set_color_alleles(:saturation, value); end

  # @return [Array<Integer>] The two brightness alleles.
  def brightness_alleles; return color_alleles(:brightness); end

  # @param value [Array<Integer>, nil] Two brightness alleles; nil derives them from the personal ID.
  def brightness_alleles=(value); set_color_alleles(:brightness, value); end

  # @brief The expressed hue gene (both alleles blended, plus the IV push).
  # @return [Float] -100 to 100.
  def hue_gene
    return HueGenetics.gene_for(self, :hue)
  end

  # @brief The expressed saturation gene (both alleles blended).
  # @return [Float] -100 to 100.
  def saturation_gene
    return HueGenetics.gene_for(self, :saturation)
  end

  # @brief The expressed brightness gene (both alleles blended).
  # @return [Float] -100 to 100.
  def brightness_gene
    return HueGenetics.gene_for(self, :brightness)
  end

  # @brief The hue rotation this Pokémon's graphics are drawn with.
  # @return [Integer] 0 to 359 (0 = normal colors).
  def hue_shift
    return HueGenetics.degrees_for(self)
  end

  # @brief Every color change this Pokémon's graphics are drawn with.
  # @return [ColorAdjust]
  def color_adjust
    return HueGenetics.color_adjust_for(self)
  end

  # @brief Whether this Pokémon looks different from the normal colors.
  # @return [Boolean]
  def hue_varied?
    return !color_adjust.identity?
  end

  alias __hue_clone clone unless method_defined?(:__hue_clone)

  # @brief Copies this Pokémon, giving the copy its own allele arrays.
  # @return [Pokemon]
  def clone
    ret = __hue_clone
    HueGenetics::TRAITS.each_value do |info|
      value = instance_variable_get(info[:ivar])
      ret.instance_variable_set(info[:ivar], value.clone) if value
    end
    return ret
  end
end
