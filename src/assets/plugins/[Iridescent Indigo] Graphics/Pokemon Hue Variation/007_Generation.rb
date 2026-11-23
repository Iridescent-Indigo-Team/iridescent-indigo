#================================================================================================
# Pokémon Iridescent Indigo Graphics/Pokemon Hue Variation - 007_Generation.rb
#================================================================================================

#==================================================================
# module HueGenetics
#==================================================================
# @brief The genetics behind each Pokémon's color variation.
# Every Pokémon carries two hue alleles, each from ALLELE_MIN to ALLELE_MAX. They don't
# depend on species: 0 means "normal colors" and the species' hue range decides how many
# degrees the extremes are worth. Both alleles are expressed (they blend), and the
# Pokémon's IVs add a small push on top:
#
#   gene  = average(allele 1, allele 2) + IV push        (-100 to 100)
#   shift = gene scaled onto the species' [min, max] range (degrees)
#
# Wild and gift Pokémon get alleles derived from their personal ID, so a Pokémon's color
# never changes and Pokémon from older saves get one too. Offspring inherit one allele
# from each parent instead (see 008_Inheritance.rb).
module HueGenetics
  # Lowest allele value
  ALLELE_MIN = -100
  # Highest allele value
  ALLELE_MAX = 100
  # Salt mixed into the personal ID so alleles don't correlate with gender/nature/ability
  PERSONAL_ID_SALT = 0x48554531   # "HUE1"

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
  # spread above 1 extreme colors are rarer than subtle ones.
  # @param personal_id [Integer]
  # @return [Array<Integer>] Two alleles.
  def alleles_from_personal_id(personal_id)
    spread = [GraphicsSettings::HUE_ALLELE_SPREAD.to_i, 1].max
    state = mix32((personal_id || 0) ^ PERSONAL_ID_SALT)
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

  # @brief How much a Pokémon's IVs push its gene, from -HUE_IV_INFLUENCE (all IVs 0) to
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

  # @brief The expressed gene: both alleles blended, plus the IV push.
  # @param pkmn [Pokemon]
  # @return [Float] ALLELE_MIN to ALLELE_MAX.
  def gene_for(pkmn)
    a, b = pkmn.hue_alleles
    return ((a + b) / 2.0 + iv_push(pkmn)).clamp(ALLELE_MIN.to_f, ALLELE_MAX.to_f)
  end

  # @brief A species' (or form's) hue range in degrees.
  # @param species [Symbol]
  # @param form [Integer]
  # @return [Array<Integer>] [most negative shift, most positive shift]
  def range_for(species, form = 0)
    ranges = GraphicsSettings::SPECIES_HUE_RANGES
    species_id = GameData::Species.try_get(species)&.species || species
    ret = ranges[:"#{species_id}_#{form}"] if form && form > 0
    ret ||= ranges[species_id]
    ret ||= GraphicsSettings::DEFAULT_HUE_RANGE
    return [[ret[0].to_i, 0].min, [ret[1].to_i, 0].max]
  end

  # @brief Scales a gene onto a hue range: 0 is no change, ALLELE_MIN is range[0] and
  # ALLELE_MAX is range[1].
  # @param gene [Numeric]
  # @param range [Array<Integer>]
  # @return [Float] Degrees (may be negative).
  def gene_to_degrees(gene, range)
    return (gene < 0) ? gene / -ALLELE_MIN.to_f * -range[0] : gene / ALLELE_MAX.to_f * range[1]
  end

  # @brief Whether a Pokémon is drawn with color variation at all.
  # @param pkmn [Pokemon]
  # @return [Boolean]
  def varies?(pkmn)
    return false if !GraphicsSettings::HUE_VARIATION_ENABLED
    return false if !pkmn || pkmn.egg?
    return false if pkmn.shiny? && !GraphicsSettings::APPLY_TO_SHINY
    return true
  end

  # @brief The hue rotation a Pokémon's graphics are drawn with.
  # @param pkmn [Pokemon]
  # @return [Integer] 0 to 359 (0 = normal colors).
  def degrees_for(pkmn)
    return 0 if !varies?(pkmn)
    degrees = gene_to_degrees(gene_for(pkmn), range_for(pkmn.species, pkmn.form))
    step = [GraphicsSettings::HUE_STEP.to_i, 1].max
    return (step * (degrees / step).round) % 360
  end

  # @brief The hue shift as a signed number of degrees (-180 to 179), for display.
  # @param pkmn [Pokemon]
  # @return [Integer]
  def signed_degrees_for(pkmn)
    degrees = degrees_for(pkmn)
    return (degrees >= 180) ? degrees - 360 : degrees
  end
end

#==================================================================
# class Pokemon
#==================================================================
# @brief Hue alleles and the hue shift they produce.
class Pokemon
  # @brief This Pokémon's two hue alleles. Pokémon without stored alleles (wild Pokémon,
  # gifts, Pokémon from older saves) get them from their personal ID the first time they're
  # asked for.
  # @return [Array<Integer>] Two values from HueGenetics::ALLELE_MIN to ALLELE_MAX.
  def hue_alleles
    @hue_alleles = HueGenetics.alleles_from_personal_id(@personalID) if !@hue_alleles
    return @hue_alleles
  end

  # @brief Sets both hue alleles.
  # @param value [Array<Integer>, nil] Two alleles; nil derives them from the personal ID again.
  def hue_alleles=(value)
    @hue_alleles = (value.nil?) ? nil : HueGenetics.normalize(value)
  end

  # @brief The expressed hue gene (both alleles blended, plus the IV push).
  # @return [Float] -100 to 100.
  def hue_gene
    return HueGenetics.gene_for(self)
  end

  # @brief The hue rotation this Pokémon's graphics are drawn with.
  # @return [Integer] 0 to 359 (0 = normal colors).
  def hue_shift
    return HueGenetics.degrees_for(self)
  end

  # @brief Whether this Pokémon looks different from the normal colors.
  # @return [Boolean]
  def hue_varied?
    return hue_shift != 0
  end

  alias __hue_clone clone unless method_defined?(:__hue_clone)

  # @brief Copies this Pokémon, giving the copy its own allele array.
  # @return [Pokemon]
  def clone
    ret = __hue_clone
    ret.hue_alleles = @hue_alleles.clone if @hue_alleles
    return ret
  end
end
