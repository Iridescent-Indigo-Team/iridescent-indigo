#===============================================================================
#
#===============================================================================
class BushBitmap
  def initialize(bitmap, isTile, depth)
    @bitmaps  = []
    @bitmap   = bitmap
    @isTile   = isTile
    @isBitmap = @bitmap.is_a?(Bitmap)
    @depth    = depth
  end

  def dispose
    @bitmaps.each { |b| b&.dispose }
  end

  def bitmap
    thisBitmap = (@isBitmap) ? @bitmap : @bitmap.bitmap
    current = (@isBitmap) ? 0 : @bitmap.currentIndex
    if !@bitmaps[current]
      if @isTile
        @bitmaps[current] = pbBushDepthTile(thisBitmap, @depth)
      else
        @bitmaps[current] = pbBushDepthBitmap(thisBitmap, @depth)
      end
    end
    return @bitmaps[current]
  end

  # A copy of a charset with the bottom depth pixels of every frame hidden:
  # the row above them is drawn at 2/3 opacity and the next at 1/3 (1px each at
  # the half-size resolution, as base Essentials' 2px rows were).
  # @param bitmap [Bitmap] the charset (4 rows of frames)
  # @param depth [Integer] pixels of each frame's bottom that are in the bush
  # @return [Bitmap]
  def pbBushDepthBitmap(bitmap, depth)
    ret = Bitmap.new(bitmap.width, bitmap.height)
    charheight = ret.height / 4
    4.times do |i|
      pbBushDepthBlt(ret, bitmap, i * charheight, charheight, depth)
    end
    return ret
  end

  # A copy of a tile graphic (one frame) with its bottom depth pixels hidden.
  # @param bitmap [Bitmap] the tile graphic
  # @param depth [Integer] pixels of the bottom that are in the bush
  # @return [Bitmap]
  def pbBushDepthTile(bitmap, depth)
    ret = Bitmap.new(bitmap.width, bitmap.height)
    pbBushDepthBlt(ret, bitmap, 0, ret.height, depth)
    return ret
  end

  private

  # Copies one frame row of bitmap into ret, leaving out its bottom depth
  # pixels and fading the two rows above them.
  # @param ret [Bitmap] destination
  # @param bitmap [Bitmap] source
  # @param y [Integer] top of the frame row in both bitmaps
  # @param charheight [Integer] height of the frame row
  # @param depth [Integer] pixels of the frame's bottom that are in the bush
  def pbBushDepthBlt(ret, bitmap, y, charheight, depth)
    cy = charheight - depth - 1
    if cy >= 0
      ret.blt(0, y, bitmap, Rect.new(0, y, ret.width, cy))
      ret.blt(0, y + cy, bitmap, Rect.new(0, y + cy, ret.width, 1), 170)
    end
    ret.blt(0, y + cy + 1, bitmap, Rect.new(0, y + cy + 1, ret.width, 1), 85) if cy + 1 >= 0
  end
end

#===============================================================================
#
#===============================================================================
class Sprite_Character < RPG::Sprite
  attr_accessor :character

  def initialize(viewport, character = nil)
    super(viewport)
    @character    = character
    @oldbushdepth = 0
    @spriteoffset = false
    if !character || character == $game_player || (character.name[/reflection/i] rescue false)
      @reflection = Sprite_Reflection.new(self, viewport)
    end
    @surfbase = Sprite_SurfBase.new(self, viewport) if character == $game_player
    self.zoom_x = TilemapRenderer::ZOOM_X
    self.zoom_y = TilemapRenderer::ZOOM_Y
    update
  end

  def groundY
    return @character.screen_y_ground
  end

  def visible=(value)
    super(value)
    @reflection.visible = value if @reflection
  end

  def dispose
    @bushbitmap&.dispose
    @bushbitmap = nil
    @charbitmap&.dispose
    @charbitmap = nil
    @reflection&.dispose
    @reflection = nil
    @surfbase&.dispose
    @surfbase = nil
    @character = nil
    super
  end

  def refresh_graphic
    return if @tile_id == @character.tile_id &&
              @character_name == @character.character_name &&
              @character_hue == @character.character_hue &&
              @oldbushdepth == @character.bush_depth
    @tile_id        = @character.tile_id
    @character_name = @character.character_name
    @character_hue  = @character.character_hue
    @oldbushdepth   = @character.bush_depth
    @charbitmap&.dispose
    @charbitmap = nil
    @bushbitmap&.dispose
    @bushbitmap = nil
    if @tile_id >= 384
      @charbitmap = pbGetTileBitmap(@character.map.tileset_name, @tile_id,
                                    @character_hue, @character.width, @character.height)
      @charbitmapAnimated = false
      @spriteoffset = false
      @cw = Game_Map::TILE_WIDTH * @character.width
      @ch = Game_Map::TILE_HEIGHT * @character.height
      self.src_rect.set(0, 0, @cw, @ch)
      self.ox = @cw / 2
      self.oy = @ch
    elsif @character_name != ""
      @charbitmap = AnimatedBitmap.new(
        "Graphics/Characters/" + @character_name, @character_hue
      )
      RPG::Cache.retain("Graphics/Characters/", @character_name, @character_hue) if @character == $game_player
      @charbitmapAnimated = true
      @spriteoffset = @character_name[/offset/i]
      @cw = @charbitmap.width / 4
      @ch = @charbitmap.height / 4
      self.ox = @cw / 2
    else
      self.bitmap = nil
      @cw = 0
      @ch = 0
      @reflection&.update
    end
    @character.sprite_size = [@cw, @ch]
  end

  def update
    return if @character.is_a?(Game_Event) && !@character.should_update?
    super
    refresh_graphic
    return if !@charbitmap
    @charbitmap.update if @charbitmapAnimated
    bushdepth = @character.bush_depth
    if bushdepth == 0
      self.bitmap = (@charbitmapAnimated) ? @charbitmap.bitmap : @charbitmap
    else
      @bushbitmap = BushBitmap.new(@charbitmap, (@tile_id >= 384), bushdepth) if !@bushbitmap
      self.bitmap = @bushbitmap.bitmap
    end
    self.visible = !@character.transparent
    if @tile_id == 0
      sx = @character.pattern * @cw
      sy = ((@character.direction - 2) / 2) * @ch
      self.src_rect.set(sx, sy, @cw, @ch)
      self.oy = (@spriteoffset rescue false) ? @ch - 8 : @ch
      self.oy -= @character.bob_height
    end
    if self.visible
      if @character.is_a?(Game_Event) && @character.name[/regulartone/i]
        self.tone.set(0, 0, 0, 0)
      else
        pbDayNightTint(self)
      end
    end
    this_x = @character.screen_x
    this_x = ((this_x - (Graphics.width / 2)) * TilemapRenderer::ZOOM_X) + (Graphics.width / 2) if TilemapRenderer::ZOOM_X != 1
    self.x = this_x
    this_y = @character.screen_y
    this_y = ((this_y - (Graphics.height / 2)) * TilemapRenderer::ZOOM_Y) + (Graphics.height / 2) if TilemapRenderer::ZOOM_Y != 1
    self.y = this_y
    self.z = @character.screen_z(@ch)
    self.opacity = @character.opacity
    self.blend_type = @character.blend_type
    if @character.animation_id != 0
      animation = $data_animations[@character.animation_id]
      animation(animation, true)
      @character.animation_id = 0
    end
    @reflection&.update
    @surfbase&.update
  end
end
