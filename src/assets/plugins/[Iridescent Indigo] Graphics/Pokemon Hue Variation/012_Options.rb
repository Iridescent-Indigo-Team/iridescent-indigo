#================================================================================================
# Pokémon Iridescent Indigo Graphics/Pokemon Hue Variation - 012_Options.rb
#================================================================================================

#==================================================================
# class PokemonSystem
#==================================================================
# @brief Stores the player's "Color variation" option.
class PokemonSystem
  # @brief How much individual Pokémon colors vary for this player.
  # @return [Integer] HueGenetics::PLAYER_FULL, PLAYER_HUE_ONLY or PLAYER_OFF
  # (GraphicsSettings::DEFAULT_PLAYER_SETTING for saves made before this option existed).
  def color_variation
    return @color_variation || GraphicsSettings::DEFAULT_PLAYER_SETTING
  end

  # @brief Sets the "Color variation" option.
  # @param value [Integer] HueGenetics::PLAYER_FULL, PLAYER_HUE_ONLY or PLAYER_OFF.
  def color_variation=(value)
    @color_variation = value.to_i.clamp(HueGenetics::PLAYER_FULL, HueGenetics::PLAYER_OFF)
  end
end

MenuHandlers.add(:options_menu, :color_variation, {
  "name"        => _INTL("Color Variation"),
  "order"       => 87,   # Just after Following Pokémon
  "type"        => EnumOption,
  "parameters"  => [_INTL("Full"), _INTL("Hue Only"), _INTL("Off")],
  "description" => _INTL("How much Pokémon colors vary. Try Hue Only or Off if changes are uncomfortable."),
  "get_proc"    => proc { next $PokemonSystem.color_variation },
  "set_proc"    => proc { |value, _scene| $PokemonSystem.color_variation = value }
})
