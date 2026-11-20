#===============================================================================
# Draws the atmosphere layers (see 004_Overworld_Atmosphere.rb).
#-------------------------------------------------------------------------------
# One renderer lives in Spriteset_Global, so every layer is drawn once, however
# many connected maps are on screen (RMXP drew a fog and a panorama per map).
#
# Performance:
#   * graphics are loaded through RPG::Cache, hue-shifted once, and split into
#     animation frames once; layers using the same graphic share them;
#   * a layer that repeats in only one direction is pre-tiled once into a
#     strip, so it's drawn as a single sprite;
#   * sprite settings (opacity, tone, blend, zoom) are only set when the
#     layer changes, and hidden layers cost nothing;
#   * graphics bigger than Settings::ATMOSPHERE_MAX_TEXTURE_SIZE aren't
#     loaded (they would fail on many Android GPUs).
#===============================================================================
module Atmosphere
  #=============================================================================
  # Shared, reference-counted layer bitmaps.
  #=============================================================================
  module Bitmaps
    @cache = {}

    module_function

    # The animation frames of a graphic.
    # @param graphic [String] path under Graphics/
    # @param hue [Integer]
    # @param frames [Integer] frames side by side in the graphic
    # @param strip [Symbol, nil] :x or :y to pre-tile the frames in that
    #   direction (for layers that repeat in one direction only)
    # @return [Array, nil] [frames (Array<Bitmap>), frame width, frame
    #   height], or nil if the graphic can't be used
    def acquire(graphic, hue, frames, strip = nil)
      key = [graphic, hue, frames, strip]
      entry = @cache[key]
      if entry
        entry[1] += 1
        return entry[0]
      end
      source = nil
      begin
        source = RPG::Cache.load_bitmap("Graphics/", graphic, hue)
      rescue StandardError
        echoln("Atmosphere: graphic Graphics/#{graphic} not found")
        return nil
      end
      max = Settings::ATMOSPHERE_MAX_TEXTURE_SIZE
      if source.width > max || source.height > max
        echoln("Atmosphere: Graphics/#{graphic} is larger than #{max}px and isn't drawn")
        source.dispose
        return nil
      end
      frames = [frames.to_i, 1].max
      width = source.width / frames
      list = []
      frames.times do |i|
        if frames == 1 && strip.nil?
          list.push(source)
          break
        end
        list.push(make_frame(source, i * width, width, source.height, strip))
      end
      height = source.height
      source.dispose if frames > 1 || strip
      result = [list, width, height]
      @cache[key] = [result, 1]
      return result
    end

    # One frame, pre-tiled across the screen when strip is :x or :y.
    def make_frame(source, x, width, height, strip)
      rect = Rect.new(x, 0, width, height)
      if strip.nil?
        bmp = Bitmap.new(width, height)
        bmp.blt(0, 0, source, rect)
        return bmp
      end
      if strip == :x
        count = (Graphics.width / width) + 2
        bmp = Bitmap.new(width * count, height)
        count.times { |i| bmp.blt(i * width, 0, source, rect) }
      else
        count = (Graphics.height / height) + 2
        bmp = Bitmap.new(width, height * count)
        count.times { |i| bmp.blt(0, i * height, source, rect) }
      end
      return bmp
    end

    # Releases bitmaps from acquire.
    def release(graphic, hue, frames, strip = nil)
      key = [graphic, hue, frames, strip]
      entry = @cache[key]
      return if !entry
      entry[1] -= 1
      return if entry[1] > 0
      entry[0][0].each { |b| b.dispose if !b.disposed? }
      @cache.delete(key)
    end
  end

  #=============================================================================
  # The sprite or plane of one layer.
  #=============================================================================
  class LayerView
    attr_reader :layer

    # @param layer [Atmosphere::Layer]
    # @param below [Viewport] viewport behind the map
    # @param above [Viewport] the map's viewport
    def initialize(layer, below, above)
      @layer = layer
      @below = below
      @above = above
      @version = -1
      @fade = -1
      @frame = -1
      @build_key = nil
      @order = 0
    end

    # @param order [Integer] drawing order among the layers
    def order=(value)
      return if @order == value
      @order = value
      @version = -1
    end

    def dispose
      @sprite&.dispose
      @sprite = nil
      Bitmaps.release(*@build_key) if @build_key && @bitmaps
      @bitmaps = nil
      @build_key = nil
    end

    # Recreates the sprite when the graphic, frames or repeating change.
    def build
      repeat_x = @layer["repeat_x"]
      repeat_y = @layer["repeat_y"]
      strip = nil
      strip = :x if repeat_x && !repeat_y
      strip = :y if repeat_y && !repeat_x
      plane = repeat_x && repeat_y
      z = @layer["z"]
      below = (z == "below" || (z.is_a?(Numeric) && z < 0))
      key = [@layer["graphic"].to_s, @layer["hue"].to_i, @layer["frames"].to_i, strip]
      return if key == @build_key && @plane == plane && @is_below == below
      dispose
      @plane = plane
      @is_below = below
      @strip = strip
      @build_key = key
      return if key[0].empty?
      acquired = Bitmaps.acquire(*key)
      if !acquired
        @build_key = nil
        return
      end
      @bitmaps, @tile_w, @tile_h = acquired
      @tile_w = [@tile_w, 1].max
      @tile_h = [@tile_h, 1].max
      viewport = below ? @below : @above
      @sprite = plane ? Plane.new(viewport) : Sprite.new(viewport)
      @sprite.bitmap = @bitmaps[0]
      @frame = 0
    end

    # @param camera [Array<Float>] camera position in world pixels
    def update(camera)
      if @version != @layer.version
        build
      end
      return if !@sprite
      opacity = @layer["opacity"].to_f * @layer.fade
      visible = @layer["visible"] && opacity > 0
      @sprite.visible = visible
      return if !visible
      if @version != @layer.version || @fade != @layer.fade
        @version = @layer.version
        @fade = @layer.fade
        @sprite.opacity = opacity
        @sprite.blend_type = @layer["blend"].to_i
        @sprite.zoom_x = @layer["zoom_x"].to_f / 100
        @sprite.zoom_y = @layer["zoom_y"].to_f / 100
        tone = @layer["tone"] || [0, 0, 0, 0]
        @sprite.tone = Tone.new(*tone)
        z = @layer["z"]
        @sprite.z = z.is_a?(Numeric) ? z : (@is_below ? @order : 3000 + @order)
      end
      if @bitmaps.length > 1 && !Atmosphere.low_quality?
        duration = [@layer["frame_duration"].to_f, 1].max / 20.0
        frame = (System.uptime / duration).floor % @bitmaps.length
        if frame != @frame
          @frame = frame
          @sprite.bitmap = @bitmaps[frame]
        end
      end
      ox = (camera[0] * @layer["parallax_x"].to_f) - @layer.scroll_pos_x - @layer["offset_x"].to_f
      oy = (camera[1] * @layer["parallax_y"].to_f) - @layer.scroll_pos_y - @layer["offset_y"].to_f
      if @plane
        @sprite.ox = ox.round
        @sprite.oy = oy.round
        return
      end
      case @strip
      when :x   # pre-tiled horizontally: wrap within one tile width
        @sprite.x = -(ox % @tile_w).round
        @sprite.y = -oy.round
      when :y
        @sprite.x = -ox.round
        @sprite.y = -(oy % @tile_h).round
      else
        @sprite.x = -ox.round
        @sprite.y = -oy.round
      end
    end
  end

  #=============================================================================
  # Keeps one LayerView per active layer.
  #=============================================================================
  class Renderer
    @@viewport = Viewport.new(0, 0, Settings::SCREEN_WIDTH, Settings::SCREEN_HEIGHT)
    @@viewport.z = -100   # behind the map, where RMXP drew panoramas

    # @param above [Viewport] the map viewport (Spriteset_Map.viewport)
    def initialize(above)
      @above = above
      @views = {}
    end

    def dispose
      @views.each_value { |v| v.dispose }
      @views.clear
    end

    def update
      manager = Atmosphere.manager
      manager.update
      @@viewport.rect.set(0, 0, Graphics.width, Graphics.height)
      layers = manager.outgoing.values + manager.layers.values
      ids = {}
      layers.each_with_index do |layer, i|
        ids[layer.object_id] = true
        view = (@views[layer.object_id] ||= LayerView.new(layer, @@viewport, @above))
        view.order = i
      end
      @views.delete_if do |id, view|
        next false if ids[id]
        view.dispose
        true
      end
      camera = manager.camera
      @views.each_value { |v| v.update(camera) }
      @@viewport.tone = $game_screen.tone if $game_screen
      @@viewport.update
    end
  end
end

#===============================================================================
# Spriteset_Global owns the renderer, so layers are drawn once.
#===============================================================================
class Spriteset_Global
  alias __atmosphere__initialize initialize unless private_method_defined?(:__atmosphere__initialize)
  alias __atmosphere__dispose dispose unless method_defined?(:__atmosphere__dispose)
  alias __atmosphere__update update unless method_defined?(:__atmosphere__update)

  def initialize
    @atmosphere = Atmosphere::Renderer.new(Spriteset_Map.viewport)
    __atmosphere__initialize
  end

  def dispose
    __atmosphere__dispose
    @atmosphere&.dispose
    @atmosphere = nil
  end

  def update
    __atmosphere__update
    @atmosphere&.update
  end
end
