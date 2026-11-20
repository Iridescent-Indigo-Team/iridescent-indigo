#===============================================================================
# Trainer class for the player
#===============================================================================
class Player < Trainer
  # @return [Integer] the character ID of the player
  attr_reader   :character_ID
  # @return [Integer] the player's outfit
  attr_reader   :outfit
  # @return [Array<Boolean>] the player's Gym Badges (true if owned)
  attr_accessor :badges
  # @return [Integer] the player's money
  attr_reader   :money
  # @return [Integer] the player's Game Corner coins
  attr_reader   :coins
  # @return [Integer] the player's battle points
  attr_reader   :battle_points
  # @return [Integer] the player's soot
  attr_reader   :soot
  # @return [Pokedex] the player's Pokédex
  attr_reader   :pokedex
  # @return [Boolean] whether the Pokédex has been obtained
  attr_accessor :has_pokedex
  # @return [Boolean] whether the Pokégear has been obtained
  attr_accessor :has_pokegear
  # @return [Boolean] whether the player has running shoes (i.e. can run)
  attr_accessor :has_running_shoes
  # @return [Boolean] whether the player has an innate ability to access Pokémon storage
  attr_accessor :has_box_link
  # @return [Boolean] whether the creator of the Pokémon Storage System has been seen
  attr_accessor :seen_storage_creator
  # @return [Boolean] whether the effect of Exp All applies innately
  attr_accessor :has_exp_all
  # @return [Boolean] whether Mystery Gift can be used from the load screen
  attr_accessor :mystery_gift_unlocked
  # @return [Array<Array>] downloaded Mystery Gift data
  attr_accessor :mystery_gifts

  def initialize(name, trainer_type)
    super
    @character_ID          = 0
    @outfit                = 0
    @badges                = [false] * 8
    @money                 = GameData::Metadata.get.start_money
    @coins                 = 0
    @battle_points         = 0
    @soot                  = 0
    @pokedex               = Pokedex.new
    @has_pokedex           = false
    @has_pokegear          = false
    @has_running_shoes     = false
    @has_box_link          = false
    @seen_storage_creator  = false
    @has_exp_all           = false
    @mystery_gift_unlocked = false
    @mystery_gifts         = []
  end

  #=============================================================================

  def character_ID=(value)
    return if @character_ID == value
    @character_ID = value
    $game_player&.refresh_charset
  end

  def outfit=(value)
    return if @outfit == value
    @outfit = value
    $game_player&.refresh_charset
  end

  def trainer_type
    return GameData::PlayerMetadata.get(@character_ID || 1).trainer_type
  end

  #=============================================================================
  # Birthday
  #=============================================================================

  # @return [Integer, nil] the month of the player's birthday (1-12), or nil
  #   if it hasn't been set
  attr_reader :birthday_month
  # @return [Integer, nil] the day of the player's birthday (1-31), or nil if
  #   it hasn't been set
  attr_reader :birthday_day

  # Sets the player's birthday (see pbSetPlayerBirthday to ask the player).
  # @param month [Integer] 1-12
  # @param day [Integer] 1-31 (limited to the length of the month)
  def set_birthday(month, day)
    validate month => Integer, day => Integer
    month = month.clamp(1, 12)
    @birthday_month = month
    @birthday_day   = day.clamp(1, pbDaysInMonth(month))
  end

  # Forgets the player's birthday.
  def clear_birthday
    @birthday_month = nil
    @birthday_day   = nil
  end

  # @return [Boolean] whether the player's birthday has been set
  def birthday_set?
    return !@birthday_month.nil? && !@birthday_day.nil?
  end

  # Whether a date is the player's birthday. A birthday on 29 February counts
  # on 28 February in years that aren't leap years.
  # @param time [Time] the date to check (the current date by default)
  # @return [Boolean]
  def birthday?(time = nil)
    return false if !birthday_set?
    time ||= pbGetTimeNow
    return false if time.mon != @birthday_month
    return true if time.day == @birthday_day
    return @birthday_month == 2 && @birthday_day == 29 && time.day == 28 &&
           pbDaysInMonth(2, time.year) == 28
  end

  # @return [Boolean] whether today is the player's birthday and it has already
  #   been celebrated this year (see #celebrate_birthday)
  def birthday_celebrated?
    return birthday? && @birthday_celebrated_year == pbGetTimeNow.year
  end

  # Marks this year's birthday as celebrated, for events that should only
  # happen once per birthday (e.g. giving the Birthday Ribbon).
  # @return [Boolean] true if it is the player's birthday and it hadn't been
  #   celebrated yet this year, false otherwise
  def celebrate_birthday
    return false if !birthday? || birthday_celebrated?
    @birthday_celebrated_year = pbGetTimeNow.year
    return true
  end

  # Sets the player's money. It can not exceed {Settings::MAX_MONEY}.
  # @param value [Integer] new money value
  def money=(value)
    validate value => Integer
    @money = value.clamp(0, Settings::MAX_MONEY)
  end

  # Sets the player's coins amount. It can not exceed {Settings::MAX_COINS}.
  # @param value [Integer] new coins value
  def coins=(value)
    validate value => Integer
    @coins = value.clamp(0, Settings::MAX_COINS)
  end

  # Sets the player's Battle Points amount. It can not exceed
  # {Settings::MAX_BATTLE_POINTS}.
  # @param value [Integer] new Battle Points value
  def battle_points=(value)
    validate value => Integer
    @battle_points = value.clamp(0, Settings::MAX_BATTLE_POINTS)
  end

  # Sets the player's soot amount. It can not exceed {Settings::MAX_SOOT}.
  # @param value [Integer] new soot value
  def soot=(value)
    validate value => Integer
    @soot = value.clamp(0, Settings::MAX_SOOT)
  end

  # @return [Integer] the number of Gym Badges owned by the player
  def badge_count
    return @badges.count { |badge| badge == true }
  end

  #=============================================================================

  # (see Pokedex#seen?)
  # Shorthand for +self.pokedex.seen?+.
  def seen?(species)
    return @pokedex.seen?(species)
  end

  # (see Pokedex#owned?)
  # Shorthand for +self.pokedex.owned?+.
  def owned?(species)
    return @pokedex.owned?(species)
  end
end
