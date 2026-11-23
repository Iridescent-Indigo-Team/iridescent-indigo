#================================================================================================
# Pokémon Iridescent Indigo Graphics/Pokemon Hue Variation - 001_ColorAdjust.rb
#================================================================================================

#==================================================================
# class ColorAdjust
#==================================================================
# @brief A hue/saturation/value adjustment for one color region.
class ColorAdjust
  attr_accessor :hue, :saturation, :value

  # @brief Creates an adjustment.
  # @param hue [Integer] Rotation in degrees (0-359).
  # @param saturation [Integer] -100 to 100.
  # @param value [Integer] -100 to 100.
  def initialize(hue = 0, saturation = 0, value = 0)
    @hue = hue
    @saturation = saturation
    @value = value
  end

  # @brief Checks whether this adjustment changes nothing.
  # @return [Boolean]
  def identity?
    return @hue % 360 == 0 && @saturation == 0 && @value == 0
  end

  # @brief A stable string identifying this adjustment (used as a cache key).
  # @return [String]
  def key
    return "hsv:#{@hue % 360},#{@saturation},#{@value}"
  end

  # @brief Checks whether two adjustments have the same effect.
  # @return [Boolean]
  def ==(other)
    return other.is_a?(ColorAdjust) && key == other.key
  end
  alias eql? ==

  # @return [Integer]
  def hash
    return key.hash
  end

  # @brief Packs this adjustment into a short code players can share.
  # @return [String]
  def to_code
    return Serializer.pack_code([@hue % 360, @saturation, @value])
  end

  # @brief Rebuilds an adjustment from a code made by to_code.
  # @param code [String]
  # @return [ColorAdjust, nil] nil if the code is invalid.
  def self.from_code(code)
    values = Serializer.unpack_code(code)
    return nil if !values || values.length != 3
    return ColorAdjust.new(values[0] % 360, values[1].clamp(-100, 100), values[2].clamp(-100, 100))
  end

  # @return [String]
  def inspect
    return "#<ColorAdjust #{key}>"
  end
end

#==================================================================
# module Recolor
#==================================================================
# @brief Recolors bitmaps in HSV space while preserving shading ramps.
module Recolor
  module_function

  # @brief Applies an adjustment to a bitmap in place.
  # Hue-only adjustments use the engine's GPU Bitmap#hue_change, which is fast enough to
  # run whenever a sprite is loaded. Saturation/value changes need the per-pixel path
  # (Pixels.map_colors!), which isn't part of this project; without it only the hue is applied.
  # Animated (GIF) bitmaps can't be changed in place; use recolored_copy for those.
  # @param bitmap [Bitmap] The layer to recolor.
  # @param adjust [ColorAdjust] The adjustment to apply.
  # @param rect [Rect, nil] Only recolor this area (e.g. a fusion's head); nil for the whole bitmap.
  def apply(bitmap, adjust, rect = nil)
    return if adjust.identity?
    if !hue_only?(adjust) && defined?(Pixels)
      Pixels.map_colors!(bitmap, rect) { |r, g, b| transform(r, g, b, adjust) }
      return
    end
    hue = adjust.hue % 360
    return if hue == 0
    if !rect || (rect.x <= 0 && rect.y <= 0 && rect.width >= bitmap.width && rect.height >= bitmap.height)
      bitmap.hue_change(hue)
      return
    end
    # Recolor just the area: copy it out, shift it and copy it back
    part = Bitmap.new(rect.width, rect.height)
    part.blt(0, 0, bitmap, rect)
    part.hue_change(hue)
    bitmap.clear_rect(rect)
    bitmap.blt(rect.x, rect.y, part, part.rect)
    part.dispose
  end

  # @brief Checks whether an adjustment only rotates hue (so the GPU fast path can be used).
  # @param adjust [ColorAdjust]
  # @return [Boolean]
  def hue_only?(adjust)
    return adjust.saturation == 0 && adjust.value == 0
  end

  # @brief Makes a recolored copy of a bitmap, keeping every frame of an animated (GIF) one.
  # @param bitmap [Bitmap] Source graphic; left unchanged.
  # @param adjust [ColorAdjust] The adjustment to apply.
  # @return [BitmapWrapper] A new bitmap with a reference count of 1.
  def recolored_copy(bitmap, adjust)
    return animated_copy(bitmap, adjust) if bitmap.respond_to?(:animated?) && bitmap.animated?
    ret = BitmapWrapper.new(bitmap.width, bitmap.height)
    ret.blt(0, 0, bitmap, bitmap.rect)
    apply(ret, adjust)
    return ret
  end

  # @brief Recolors each frame of an animated bitmap into a new animated bitmap.
  # @param bitmap [Bitmap] An animated source graphic.
  # @param adjust [ColorAdjust]
  # @return [BitmapWrapper]
  def animated_copy(bitmap, adjust)
    ret = nil
    bitmap.frame_count.times do |i|
      frame = bitmap.snap_to_bitmap(i)
      frame.resetRef if frame.respond_to?(:resetRef)   # Allocated without initialize
      apply(frame, adjust)
      if ret
        ret.add_frame(frame)
      else
        ret = BitmapWrapper.new(frame.width, frame.height)
        ret.blt(0, 0, frame, frame.rect)
      end
      frame.dispose
    end
    ret ||= BitmapWrapper.new(bitmap.width, bitmap.height)
    if ret.animated?
      ret.frame_rate = bitmap.frame_rate
      ret.looping    = bitmap.looping
    end
    return ret
  end

  # @brief Applies an adjustment to one area of a bitmap in place.
  # @param bitmap [Bitmap]
  # @param rect [Rect]
  # @param adjust [ColorAdjust]
  def apply_rect(bitmap, rect, adjust)
    apply(bitmap, adjust, rect)
  end

  # @brief Transforms a single RGB color.
  # @return [Array<Integer>] The new [r, g, b].
  def transform(r, g, b, adjust)
    h, s, v = ColorMath.rgb_to_hsv(r, g, b)
    h = (h + adjust.hue) % 360
    s = ColorMath.shift(s, adjust.saturation / 100.0)
    v = ColorMath.shift(v, adjust.value / 100.0)
    return ColorMath.hsv_to_rgb(h, s, v)
  end

  # @brief Moves a 0-1 channel proportionally toward 1 (positive) or 0 (negative).
  # @see ColorMath.shift
  def shift(channel, amount)
    return ColorMath.shift(channel, amount)
  end

  # @brief Converts RGB (0-255) to HSV (h: 0-360, s/v: 0-1).
  # @see ColorMath.rgb_to_hsv
  def rgb_to_hsv(r, g, b)
    return ColorMath.rgb_to_hsv(r, g, b)
  end

  # @brief Converts HSV back to RGB (0-255).
  # @see ColorMath.hsv_to_rgb
  def hsv_to_rgb(h, s, v)
    return ColorMath.hsv_to_rgb(h, s, v)
  end
end