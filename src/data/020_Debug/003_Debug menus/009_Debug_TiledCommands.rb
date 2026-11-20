#===============================================================================
# Debug menu changes for games whose maps are made in Tiled (src/tiled).
#-------------------------------------------------------------------------------
# The Tiled compiler writes Data/tiled_build.dat. In such builds the maps,
# tilesets, map metadata, encounters and connections are compiled from
# src/tiled every build, so the in-game editors that would change them here
# would lose their changes on the next build. Those options say where to make
# the change instead:
#   map_connections.txt -> place the maps next to each other in the Tiled
#                          world (src/tiled/maps/pokessentials.world)
#   encounters.txt      -> the map's "encounters" property in Tiled
#   map_metadata.txt    -> the map's "metadata" property in Tiled
#   terrain tags        -> the TileData of the tile in Tiled's tileset editor
#   fix invalid tiles   -> `make validate-tiled` reports invalid tiles
# Everything else in the debug menu works as before.
#===============================================================================
module TiledBuild
  # Marker written by tools/importer/tiled (tiled_compiler.py build).
  MARKER = "Data/tiled_build.dat"

  module_function

  # @return [Boolean] true if this build's maps were compiled from Tiled
  def active?
    @active = pbRgssExists?(MARKER) if @active.nil?
    return @active
  end

  # Replaces a debug option's effect with a message pointing to Tiled.
  # @param option [Symbol]
  # @param message [String]
  def redirect(option, message)
    MenuHandlers.each(:debug_menu) do |id, hash|
      next if id != option
      original = hash["effect"]
      hash["effect"] = proc { |*args|
        if TiledBuild.active?
          pbMessage(message)
        else
          original&.call(*args)
        end
      }
    end
  end
end

TiledBuild.redirect(:set_map_connections,
                    _INTL("This game's maps are made in Tiled. Connect maps by placing them next to each other in the Tiled world (src/tiled/maps/pokessentials.world)."))
TiledBuild.redirect(:set_encounters,
                    _INTL("This game's maps are made in Tiled. Edit encounters in the map's \"encounters\" property in Tiled."))
TiledBuild.redirect(:set_map_metadata,
                    _INTL("This game's maps are made in Tiled. Edit map metadata in the map's \"metadata\" property in Tiled."))
TiledBuild.redirect(:set_terrain_tags,
                    _INTL("This game's maps are made in Tiled. Edit terrain tags in the tile's TileData in Tiled's tileset editor."))
TiledBuild.redirect(:fix_invalid_tiles,
                    _INTL("This game's maps are made in Tiled. Run `make validate-tiled` to find invalid tiles."))
