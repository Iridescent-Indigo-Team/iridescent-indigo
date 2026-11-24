#================================================================================================
# Pokémon Iridescent Indigo Graphics - 001_Core.rb
#================================================================================================

#==================================================================
# module DevLog
#==================================================================
# @brief Small helpers for failing softly: graphics code should log a problem and carry
# on with the unchanged graphic rather than crash the game.
module DevLog
  module_function

  # @brief Runs a block, logging and swallowing any error it raises.
  # @param message [String] What was being attempted, written to the log on failure.
  # @yieldreturn [Object] The block's result.
  # @return [Object, nil] The block's result, or nil if it raised an error.
  def guard(message)
    return yield
  rescue StandardError => e
    log("#{message}: #{e.class}: #{e.message}")
    return nil
  end

  # @brief Writes a line to the console and, when debugging, to the debug log.
  # @param message [String]
  def log(message)
    text = "[Graphics] #{message}"
    echoln(text) if defined?(echoln)
    PBDebug.log(text) if defined?(PBDebug) && $INTERNAL
  end
end

#==================================================================
# module ColorMath
#==================================================================
# @brief Color conversions used by the saturation/brightness recolor.
module ColorMath
  module_function

  # @brief Converts RGB to HSV.
  # @param r [Integer] 0-255.
  # @param g [Integer] 0-255.
  # @param b [Integer] 0-255.
  # @return [Array<Float>] [hue 0-360, saturation 0-1, value 0-1]
  def rgb_to_hsv(r, g, b)
    max = [r, g, b].max
    min = [r, g, b].min
    delta = (max - min).to_f
    v = max / 255.0
    s = (max == 0) ? 0.0 : delta / max
    return [0.0, s, v] if delta == 0
    if max == r
      h = 60 * (((g - b) / delta) % 6)
    elsif max == g
      h = 60 * (((b - r) / delta) + 2)
    else
      h = 60 * (((r - g) / delta) + 4)
    end
    return [h % 360, s, v]
  end

  # @brief Converts HSV back to RGB.
  # @param h [Numeric] Hue in degrees (any value; wrapped to 0-360).
  # @param s [Float] Saturation 0-1.
  # @param v [Float] Value (brightness) 0-1.
  # @return [Array<Integer>] [r, g, b], each 0-255.
  def hsv_to_rgb(h, s, v)
    h = h % 360
    c = v * s
    x = c * (1 - (((h / 60.0) % 2) - 1).abs)
    m = v - c
    r, g, b = case (h / 60).floor
              when 0 then [c, x, 0]
              when 1 then [x, c, 0]
              when 2 then [0, c, x]
              when 3 then [0, x, c]
              when 4 then [x, 0, c]
              else        [c, 0, x]
              end
    return [((r + m) * 255).round.clamp(0, 255), ((g + m) * 255).round.clamp(0, 255),
            ((b + m) * 255).round.clamp(0, 255)]
  end

  # @brief Moves a 0-1 channel proportionally toward 1 (positive amount) or 0 (negative),
  # so it can never overshoot either end.
  # @param channel [Float] 0-1.
  # @param amount [Float] -1.0 to 1.0.
  # @return [Float] 0-1.
  def shift(channel, amount)
    return channel + ((1.0 - channel) * amount) if amount > 0
    return channel * (1.0 + amount)
  end
end

#==================================================================
# module Pixels
#==================================================================
# @brief Fast whole-bitmap pixel edits through Bitmap#raw_data (RGBA bytes).
module Pixels
  module_function

  # @brief Replaces every opaque color of a bitmap (or an area of it) in place.
  # The block runs once per distinct color, so pixel art with few colors is quick.
  # Transparent pixels and alpha are left as they are.
  # @param bitmap [Bitmap]
  # @param rect [Rect, nil] Area to change; nil for the whole bitmap.
  # @yieldparam r [Integer]
  # @yieldparam g [Integer]
  # @yieldparam b [Integer]
  # @yieldreturn [Array<Integer>, nil] The new [r, g, b], or nil to keep the color.
  def map_colors!(bitmap, rect = nil)
    width = bitmap.width
    pixels = bitmap.raw_data.unpack("N*")   # Each pixel is 0xRRGGBBAA
    memo = {}
    x0, y0, x1, y1 = bounds(bitmap, rect)
    (y0...y1).each do |y|
      row = y * width
      (x0...x1).each do |x|
        px = pixels[row + x]
        alpha = px & 0xFF
        next if alpha == 0
        rgb = px >> 8
        out = memo.fetch(rgb) do
          rgb_new = yield((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF)
          memo[rgb] = (rgb_new) ? (rgb_new[0] << 16) | (rgb_new[1] << 8) | rgb_new[2] : rgb
        end
        pixels[row + x] = (out << 8) | alpha
      end
    end
    bitmap.raw_data = pixels.pack("N*")
  end

  # @brief The pixel bounds of an area, clipped to a bitmap.
  # @param bitmap [Bitmap]
  # @param rect [Rect, nil]
  # @return [Array<Integer>] [x0, y0, x1, y1] (x1/y1 exclusive)
  def bounds(bitmap, rect)
    return [0, 0, bitmap.width, bitmap.height] if !rect
    return [rect.x.clamp(0, bitmap.width), rect.y.clamp(0, bitmap.height),
            (rect.x + rect.width).clamp(0, bitmap.width), (rect.y + rect.height).clamp(0, bitmap.height)]
  end
end
