#===============================================================================
#
#===============================================================================
class PokemonPokedexInfo_Scene
  alias paldea_pbUpdateDummyPokemon pbUpdateDummyPokemon
  def pbUpdateDummyPokemon
    @sprites["formback"]&.zoom_x = 1.0
    @sprites["formback"]&.zoom_y = 1.0
    paldea_pbUpdateDummyPokemon
    # Pokessentials: halved from the pack's values (width > 200, y = 256) to
    # match the 256x192 screen and the halved sprites in build/Graphics.
    if @sprites["formback"] && @sprites["formback"].bitmap.width > 100
      @sprites["formback"].zoom_x *= 2 / 3.0
      @sprites["formback"].zoom_y *= 2 / 3.0
      @sprites["formback"].y = 128
    end
  end
end