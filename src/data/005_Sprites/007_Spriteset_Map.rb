#===============================================================================
# Unused.
#===============================================================================
class ClippableSprite < Sprite_Character
  def initialize(viewport, event, tilemap)
    @tilemap = tilemap
    @_src_rect = Rect.new(0, 0, 0, 0)
    super(viewport, event)
  end

  def update
    super
    @_src_rect = self.src_rect
    tmright = (@tilemap.map_data.xsize * Game_Map::TILE_WIDTH) - @tilemap.ox
    echoln "x=#{self.x},ox=#{self.ox},tmright=#{tmright},tmox=#{@tilemap.ox}"
    if @tilemap.ox - self.ox < -self.x
      # clipped on left
      diff = -self.x - @tilemap.ox + self.ox
      self.src_rect = Rect.new(@_src_rect.x + diff, @_src_rect.y,
                               @_src_rect.width - diff, @_src_rect.height)
      echoln "clipped out left: #{diff} #{@tilemap.ox - self.ox} #{self.x}"
    elsif tmright - self.ox < self.x
      # clipped on right
      diff = self.x - tmright + self.ox
      self.src_rect = Rect.new(@_src_rect.x, @_src_rect.y,
                               @_src_rect.width - diff, @_src_rect.height)
      echoln "clipped out right: #{diff} #{tmright + self.ox} #{self.x}"
    else
      echoln "-not- clipped out left: #{diff} #{@tilemap.ox - self.ox} #{self.x}"
    end
  end
end

#===============================================================================
#
#===============================================================================
class Spriteset_Map
  attr_reader :map

  @@viewport0 = Viewport.new(0, 0, Settings::SCREEN_WIDTH, Settings::SCREEN_HEIGHT)   # Panorama
  @@viewport0.z = -100
  @@viewport1 = Viewport.new(0, 0, Settings::SCREEN_WIDTH, Settings::SCREEN_HEIGHT)   # Map, events, player, fog
  @@viewport1.z = 0
  @@viewport3 = Viewport.new(0, 0, Settings::SCREEN_WIDTH, Settings::SCREEN_HEIGHT)   # Flashing
  @@viewport3.z = 500

  # For access by Spriteset_Global.
  def self.viewport
    return @@viewport1
  end

  def initialize(map = nil)
    @map = (map) ? map : $game_map
    $scene.map_renderer.add_tileset(@map.tileset_name)
    @map.autotile_names.each { |filename| $scene.map_renderer.add_autotile(filename) }
    $scene.map_renderer.add_extra_autotiles(@map.tileset_id)
    # Fogs and panoramas are drawn once for all maps by the atmosphere
    # renderer in Spriteset_Global (012_Overworld/001_Overworld visuals).
    @character_sprites = []
    @map.events.keys.sort.each do |i|
      sprite = Sprite_Character.new(@@viewport1, @map.events[i])
      @character_sprites.push(sprite)
    end
    EventHandlers.trigger(:on_new_spriteset_map, self, @@viewport1)
    update
  end

  def dispose
    if $scene.is_a?(Scene_Map)
      $scene.map_renderer.remove_tileset(@map.tileset_name)
      @map.autotile_names.each { |filename| $scene.map_renderer.remove_autotile(filename) }
      $scene.map_renderer.remove_extra_autotiles(@map.tileset_id)
    end
    @character_sprites.each { |sprite| sprite.dispose }
    @character_sprites.clear
  end

  def getAnimations
    return @usersprites
  end

  def restoreAnimations(anims)
    @usersprites = anims
  end

  def update
    @@viewport1.rect.set(0, 0, Graphics.width, Graphics.height)
    @@viewport1.ox = 0
    @@viewport1.oy = 0
    @@viewport1.ox += $game_screen.shake
    @character_sprites.each do |sprite|
      sprite.update
    end
    @@viewport1.tone = $game_screen.tone
    @@viewport3.color = $game_screen.flash_color
    @@viewport1.update
    @@viewport3.update
  end
end
