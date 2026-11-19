# Using mkxp-z v2.4.2/c9378cf - built 2023-07-07
# https://github.com/mkxp-z/mkxp-z/actions/runs/5482601942
$VERBOSE = nil
Font.default_shadow = false if Font.respond_to?(:default_shadow)
Encoding.default_internal = Encoding::UTF_8
Encoding.default_external = Encoding::UTF_8

def pbSetWindowText(string)
  System.set_window_title(string || System.game_title)
end

class Bitmap
  attr_accessor :text_offset_y

  alias mkxp_draw_text draw_text unless method_defined?(:mkxp_draw_text)

  def draw_text(x, y, width, height = nil, text = "", align = 0)
    if x.is_a?(Rect)
      x.y -= (@text_offset_y || 0)
      # rect, string & alignment
      mkxp_draw_text(x, y, width)
    else
      y -= (@text_offset_y || 0)
      height = text_size(text).height
      mkxp_draw_text(x, y, width, height, text, align)
    end
  end
end

# True when running on Android (the mkxp-z Android app).
def pbIsAndroid?
  return System.platform[/Android/i] ? true : false
end

# Sets the window size.
# factor: 0 = 1x, 1 = 2x, 2 = 3x, 3 = 4x (of Settings::SCREEN_WIDTH/HEIGHT),
#         4 or negative = fullscreen.
# Only whole-number scales are used so every game pixel stays the same size.
# When the player resizes the window by hand, mkxp-z keeps the picture pixel
# perfect itself (integer scaling with black borders, see src/mkxp.json).
# On Android the game always fills the screen.
def pbSetResizeFactor(factor)
  if !$ResizeInitialized
    Graphics.resize_screen(Settings::SCREEN_WIDTH, Settings::SCREEN_HEIGHT)
    # resize_screen also resizes the window to 1x, but asynchronously. Wait
    # for that to happen, otherwise the resize below thinks the window already
    # has the wanted size and is skipped.
    10.times do
      break if (Graphics.scale - 1.0).abs < 0.01
      Graphics.update
    end
    $ResizeInitialized = true
  end
  if pbIsAndroid? || factor < 0 || factor >= 4
    Graphics.fullscreen = true if !Graphics.fullscreen
  else
    Graphics.fullscreen = false if Graphics.fullscreen
    scale = factor.to_i + 1
    # resize_window is used instead of Graphics.scale=, which can skip the
    # resize right after resize_screen because it compares against the old
    # window size.
    Graphics.resize_window(Settings::SCREEN_WIDTH * scale, Settings::SCREEN_HEIGHT * scale)
    Graphics.center
  end
end

if System::VERSION != Essentials::MKXPZ_VERSION
  printf(sprintf("\e[1;33mWARNING: mkxp-z version %s detected, but this version of Pokémon Essentials was designed for mkxp-z version %s.\e[0m\r\n",
                 System::VERSION, Essentials::MKXPZ_VERSION))
  printf("\e[1;33mWARNING: Pokémon Essentials may not work properly.\e[0m\r\n")
end
