#================================================================================================
# Pokémon Iridescent Indigo Graphics/Pokemon Patterns - 006_Pokedex.rb
#================================================================================================
# The Pokédex records which patterns the player has seen, for each species and form. They
# are listed on the existing Forms page, after the form they were seen in (e.g. "Spotted"),
# and choosing one shows its sprites on the entry. No new graphics are needed.

#==================================================================
# module PatternDex
#==================================================================
# @brief Helpers shared by the Pokédex and the battle scripts.
module PatternDex
  module_function

  # @brief The form number a Pokémon is recorded under in the Pokédex (as in
  # Player::Pokedex#register_last_seen).
  # @param pkmn [Pokemon]
  # @return [Integer]
  def dex_form(pkmn)
    species_data = pkmn.species_data
    form = species_data.pokedex_form
    form = 0 if species_data.form_name.nil? || species_data.form_name.empty?
    return form
  end

  # @brief Records the pattern a battler appears to have (its Illusion's, if any).
  # @param battle [Battle, SafariBattle]
  # @param battler [Battle::Battler, Pokemon, nil]
  def register_battler(battle, battler)
    return if !battler || !battle.instance_variable_get(:@internalBattle)
    return if battler.is_a?(Pokemon)   # Already recorded by Player::Pokedex#register
    pkmn = (battler.respond_to?(:displayPokemon)) ? battler.displayPokemon : nil
    pkmn ||= battler.pokemon if battler.respond_to?(:pokemon)
    battle.pbPlayer&.pokedex&.register_pattern(pkmn)
  end

  # @brief The patterns of a species to list for a form on the Forms page: the seen ones,
  # or all of them if Settings::DEX_SHOWS_ALL_FORMS is on. In the order the line defines
  # them.
  # @param species [Symbol]
  # @param form [Integer]
  # @return [Array<Symbol>]
  def listed_patterns(species, form)
    return [] if !PatternData.enabled?
    ids = PatternData.ids_for(species)
    return ids if Settings::DEX_SHOWS_ALL_FORMS
    return ids.select { |pattern| $player.pokedex.seen_pattern?(species, pattern, form) }
  end
end

#==================================================================
# class Player::Pokedex
#==================================================================
# @brief Seen patterns. The hashes are created when first needed, so saves made before
# patterns existed work.
class Player
  class Pokedex
    alias __pattern_clear clear unless method_defined?(:__pattern_clear)
    alias __pattern_register register unless method_defined?(:__pattern_register)
    alias __pattern_register_last_seen register_last_seen unless method_defined?(:__pattern_register_last_seen)

    # @brief Clears the Pokédex, including seen patterns.
    def clear
      __pattern_clear
      @seen_patterns      = {}
      @last_seen_patterns = {}
    end

    # @brief Registers a Pokémon as seen. If given a Pokémon (rather than a species), its
    # pattern is recorded too.
    def register(species, gender = 0, form = 0, shiny = false, should_refresh_dexes = true)
      __pattern_register(species, gender, form, shiny, should_refresh_dexes)
      register_pattern(species) if species.is_a?(Pokemon)
    end

    # @brief Registers a Pokémon as the one most recently seen, and shows its pattern on
    # its Pokédex entry.
    # @param pkmn [Pokemon]
    def register_last_seen(pkmn)
      __pattern_register_last_seen(pkmn)
      register_pattern(pkmn)
      set_last_pattern_seen(pkmn.species, (pkmn.patterned?) ? pkmn.pattern : nil)
    end

    # @brief Records a Pokémon's pattern as seen (nothing for eggs or "no pattern").
    # @param pkmn [Pokemon, nil]
    def register_pattern(pkmn)
      return if !pkmn.is_a?(Pokemon) || pkmn.egg? || !pkmn.patterned?
      @seen_patterns ||= {}
      forms = ((@seen_patterns[pkmn.species] ||= {})[pkmn.pattern] ||= [])
      form = PatternDex.dex_form(pkmn)
      forms.push(form) if !forms.include?(form)
    end

    # @brief Whether a pattern has been seen.
    # @param species [Symbol]
    # @param pattern [Symbol]
    # @param form [Integer, nil] Only in this form (nil for any form).
    # @return [Boolean]
    def seen_pattern?(species, pattern, form = nil)
      forms = (@seen_patterns || {}).dig(species, pattern)
      return false if !forms
      return form.nil? || forms.include?(form)
    end

    # @brief The patterns seen of a species.
    # @param species [Symbol]
    # @return [Array<Symbol>]
    def seen_patterns(species)
      return ((@seen_patterns || {})[species] || {}).keys
    end

    # @brief How many patterns of a species have been seen.
    # @param species [Symbol]
    # @return [Integer]
    def seen_patterns_count(species)
      return seen_patterns(species).length
    end

    # @brief The pattern shown on a species' Pokédex entry.
    # @param species [Symbol]
    # @return [Symbol, nil] nil for the normal sprites.
    def last_pattern_seen(species)
      return (@last_seen_patterns || {})[species]
    end

    # @brief Sets the pattern shown on a species' Pokédex entry.
    # @param species [Symbol]
    # @param pattern [Symbol, nil] nil for the normal sprites.
    def set_last_pattern_seen(species, pattern)
      @last_seen_patterns ||= {}
      @last_seen_patterns[species] = pattern
    end
  end
end

#==================================================================
# class PokemonSprite
#==================================================================
# @brief Species sprites with a pattern, for the Pokédex.
class PokemonSprite < Sprite
  # @brief Shows a species' sprite with a pattern, or its normal sprite if the pattern has
  # no sprite.
  # @param species [Symbol]
  # @param gender [Integer]
  # @param form [Integer]
  # @param shiny [Boolean]
  # @param pattern [Symbol, nil]
  # @param back [Boolean]
  def setPatternSpeciesBitmap(species, gender, form, shiny, pattern, back = false)
    file = PatternSprites.resolve("Graphics/Pokemon/", (back) ? "Back" : "Front", species, form, gender,
                                  shiny, false, pattern)
    return setSpeciesBitmap(species, gender, form, shiny, false, back) if !file
    @_iconbitmap&.dispose
    @_iconbitmap = AnimatedBitmap.new(file)
    self.bitmap = @_iconbitmap.bitmap
    changeOrigin
  end
end

#==================================================================
# class PokemonSpeciesIconSprite
#==================================================================
# @brief Species icons with a pattern, for the Pokédex.
class PokemonSpeciesIconSprite < Sprite
  # @return [Symbol, nil] The pattern the icon is drawn with.
  attr_reader :pattern

  alias __pattern_refresh refresh unless method_defined?(:__pattern_refresh)

  # @brief Sets the pattern (takes effect when the icon next refreshes).
  # @param value [Symbol, nil]
  def pattern=(value)
    @pattern = value
  end

  # @brief Reloads the icon, using the pattern's icon if there is one.
  def refresh
    file = nil
    if @pattern && @species
      file = PatternSprites.resolve("Graphics/Pokemon/", "Icons", @species, @form, @gender, @shiny == true,
                                    false, @pattern)
    end
    return __pattern_refresh if !file
    @animBitmap&.dispose
    @animBitmap = AnimatedBitmap.new(file)
    self.bitmap = @animBitmap.bitmap
    self.src_rect.width  = @animBitmap.height
    self.src_rect.height = @animBitmap.height
    @frames_count = @animBitmap.width / @animBitmap.height
    @current_frame = 0 if @current_frame >= @frames_count
    changeOrigin
  end
end

#==================================================================
# class PokemonPokedexInfo_Scene
#==================================================================
# @brief Lists seen patterns on the Forms page, and shows the chosen one's sprites.
# Entries of @available are [name, gender, form] for forms, as in the engine, and
# [name, gender, form, pattern] for patterns.
class PokemonPokedexInfo_Scene
  alias __pattern_pbGetAvailableForms pbGetAvailableForms unless method_defined?(:__pattern_pbGetAvailableForms)
  alias __pattern_pbUpdateDummyPokemon pbUpdateDummyPokemon unless method_defined?(:__pattern_pbUpdateDummyPokemon)

  # @brief The forms of the species, each followed by the patterns seen in it.
  # @return [Array<Array>]
  def pbGetAvailableForms
    ret = __pattern_pbGetAvailableForms
    return ret if !PatternData.has_patterns?(@species)
    with_patterns = []
    ret.each do |entry|
      with_patterns.push(entry)
      PatternDex.listed_patterns(@species, entry[2]).each do |pattern|
        name = PatternData.name_for(@species, pattern)
        name = _INTL("{1} ({2})", name, entry[0]) if entry[0] && !entry[0].empty?
        with_patterns.push([name, entry[1], entry[2], pattern])
      end
    end
    return with_patterns
  end

  # @brief The pattern the entry is showing, if it's still one the Forms page lists.
  # @param species [Symbol]
  # @param form [Integer]
  # @return [Symbol, nil]
  def pbCurrentPattern(species, form)
    pattern = $player.pokedex.last_pattern_seen(species)
    return nil if !pattern || !PatternDex.listed_patterns(species, form).include?(pattern)
    return pattern
  end

  # @brief Whether an @available entry is the one being shown.
  # @param entry [Array]
  # @return [Boolean]
  def pbShownEntry?(entry)
    return entry[1] == @gender && entry[2] == @form && entry[3] == @pattern
  end

  # @brief Shows the species' last seen form, with its chosen pattern if any.
  def pbUpdateDummyPokemon
    species = @dexlist[@index][:species]
    _gender, form, _shiny = $player.pokedex.last_form_seen(species)
    @pattern = pbCurrentPattern(species, form)
    @sprites["formicon"].pattern = @pattern if @sprites["formicon"]
    __pattern_pbUpdateDummyPokemon
    return if !@pattern
    @sprites["infosprite"].setPatternSpeciesBitmap(@species, @gender, @form, @shiny, @pattern)
    @sprites["formfront"]&.setPatternSpeciesBitmap(@species, @gender, @form, @shiny, @pattern)
    # Pattern sprites are the same size as the normal ones, so the position and zoom set
    # for the normal back sprite (by the engine and the Generation 9 Pack) still fit
    @sprites["formback"]&.setPatternSpeciesBitmap(@species, @gender, @form, @shiny, @pattern, true)
  end

  # @brief Draws the Forms page, naming the chosen pattern.
  # Mirrors the engine's version, matching entries by pattern too.
  def drawPageForms
    @sprites["background"].setBitmap(_INTL("Graphics/UI/Pokedex/bg_forms"))
    overlay = @sprites["overlay"].bitmap
    base   = Color.new(88, 88, 80)
    shadow = Color.new(168, 184, 184)
    # Write species and form name
    formname = ""
    @available.each do |i|
      next if !pbShownEntry?(i)
      formname = i[0]
      break
    end
    textpos = [
      [GameData::Species.get(@species).name, Graphics.width / 2, Graphics.height - 41, :center, base, shadow],
      [formname, Graphics.width / 2, Graphics.height - 25, :center, base, shadow]
    ]
    # Draw all text
    pbDrawTextPositions(overlay, textpos)
  end

  # @brief Lets the player choose a form or pattern to show.
  # Mirrors the engine's version, also remembering the chosen pattern.
  def pbChooseForm
    index = 0
    @available.length.times do |i|
      next if !pbShownEntry?(@available[i])
      index = i
      break
    end
    oldindex = -1
    loop do
      if oldindex != index
        $player.pokedex.set_last_form_seen(@species, @available[index][1], @available[index][2])
        $player.pokedex.set_last_pattern_seen(@species, @available[index][3])
        pbUpdateDummyPokemon
        drawPage(@page)
        @sprites["uparrow"].visible   = (index > 0)
        @sprites["downarrow"].visible = (index < @available.length - 1)
        oldindex = index
      end
      Graphics.update
      Input.update
      pbUpdate
      if Input.trigger?(Input::UP)
        pbPlayCursorSE
        index = (index + @available.length - 1) % @available.length
      elsif Input.trigger?(Input::DOWN)
        pbPlayCursorSE
        index = (index + 1) % @available.length
      elsif Input.trigger?(Input::BACK)
        pbPlayCancelSE
        break
      elsif Input.trigger?(Input::USE)
        pbPlayDecisionSE
        break
      end
    end
    @sprites["uparrow"].visible   = false
    @sprites["downarrow"].visible = false
  end
end
