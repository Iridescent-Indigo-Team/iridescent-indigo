#================================================================================================
# Pokémon Iridescent Indigo Graphics/Pokemon Patterns - 001_Sprites.rb
#================================================================================================


#==================================================================
# class Pokemon
#==================================================================
# @brief Pattern attribute for Pokemon.
class Pokemon
  attr_writer :pattern

  def pattern
    @pattern = PatternData.roll(self) if @pattern.nil? && PatternData.has_patterns?(species)
    @pattern
  end
end