#===============================================================================
# renderer_test.rb
#-------------------------------------------------------------------------------
# Drives Atmosphere::Renderer
# (src/data/012_Overworld/001_Overworld visuals/005_Overworld_AtmosphereRenderer.rb)
# with stand-ins for the engine's sprite classes, to check it positions,
# animates, shares and disposes layer sprites as intended. Run by
# test_tiled.py; prints "ok" when every check passes.
#===============================================================================
ROOT = File.expand_path("../../../..", __dir__)

# Reuse the manager test's engine stubs, without running its checks.
module System
  @now = 0.0
  class << self
    attr_accessor :now
    def uptime; @now; end
  end
end
module Settings
  SCREEN_WIDTH = 256
  SCREEN_HEIGHT = 192
  ATMOSPHERE_LOW_QUALITY = false
  ATMOSPHERE_LOW_QUALITY_ON_ANDROID = false
  ATMOSPHERE_MAX_TEXTURE_SIZE = 4096
  ATMOSPHERE_FADE_FRAMES = 20
end
class Tone
  attr_reader :red, :green, :blue, :gray
  def initialize(r, g, b, gray = 0); @red, @green, @blue, @gray = r, g, b, gray; end
end
class Rect
  def initialize(*a); @a = a; end
  def set(*a); @a = a; end
end
module Graphics
  def self.width; 256; end
  def self.height; 192; end
end
class Bitmap
  attr_reader :width, :height
  @@live = 0
  def self.live; @@live; end
  def initialize(w, h); @width, @height = w, h; @disposed = false; @@live += 1; end
  def blt(*_); end
  def dispose; @@live -= 1 unless @disposed; @disposed = true; end
  def disposed?; @disposed; end
end
module RPG
  module Cache
    def self.load_bitmap(_folder, file, _hue = 0)
      raise "missing" if file.include?("Missing")
      return Bitmap.new(file.include?("Huge") ? 5000 : 192, 64)
    end
  end
end
class Viewport
  attr_accessor :z, :tone
  def initialize(*_); @rect = Rect.new; end
  def rect; @rect; end
  def update; end
end
class Sprite
  @@live = 0
  def self.live; @@live; end
  attr_accessor :bitmap, :x, :y, :z, :ox, :oy, :opacity, :blend_type, :zoom_x, :zoom_y, :tone, :visible
  attr_reader :viewport
  def initialize(viewport = nil); @viewport = viewport; @@live += 1; end
  def dispose; @@live -= 1; end
end
class Plane < Sprite; end
class Game_Map
  TILE_WIDTH = 16
  TILE_HEIGHT = 16
  X_SUBPIXELS = 4
  Y_SUBPIXELS = 4
  attr_accessor :map_id, :display_x, :display_y, :tileset_id, :panorama_name, :fog_name
  def initialize(id); @map_id = id; @display_x = @display_y = 0; @tileset_id = 1; @panorama_name = @fog_name = ""; end
end
class PokemonGlobalMetadata; end
class Interpreter; def command_204; end; end
class Spriteset_Map; def self.viewport; @vp ||= Viewport.new; end; end
class Spriteset_Global
  def initialize; end
  def dispose; end
  def update; end
end
def echoln(msg); ($echo ||= []) << msg; end
def pbRgssExists?(_f); true; end
def load_data(_f); Marshal.load(Marshal.dump($atmosphere_data)); end
def nil_or_empty?(s); s.nil? || s.empty?; end
def pbIsAndroid?; false; end
def lerp(a, b, d, s, n = nil); s = n - s if n; return b if d <= 0 || s >= d; a + ((b - a) * s / d.to_f); end

def layer(name, extra = {})
  { "name" => name, "graphic" => "Fogs/#{name}", "z" => "above", "parallax_x" => 1.0, "parallax_y" => 0.5,
    "scroll_x" => 0.0, "scroll_y" => 0.0, "opacity" => 100, "repeat_x" => true, "repeat_y" => true,
    "frames" => 1, "frame_duration" => 5, "tone" => [0, 0, 0, 0], "zoom_x" => 100, "zoom_y" => 100,
    "blend" => 0, "hue" => 0, "offset_x" => 0, "offset_y" => 0, "visible" => true }.merge(extra)
end
$atmosphere_data = {
  "groups" => {
    "a" => { "layers" => [layer("plane"), layer("anim", "frames" => 3, "repeat_y" => false, "z" => "below"),
                          layer("still", "repeat_x" => false, "repeat_y" => false),
                          layer("Missing"), layer("Huge")] },
    "b" => { "layers" => [layer("other")] }
  },
  "maps" => { "1" => { "group" => "a", "layers" => [] }, "2" => { "group" => "b", "layers" => [] } },
  "world" => { "1" => [10, 0] }
}
$game_screen = nil
load File.join(ROOT, "src/data/012_Overworld/001_Overworld visuals/004_Overworld_Atmosphere.rb")
load File.join(ROOT, "src/data/012_Overworld/001_Overworld visuals/005_Overworld_AtmosphereRenderer.rb")

$failures = 0
def check(label, cond)
  return if cond
  $failures += 1
  puts "FAIL: #{label}"
end

$PokemonGlobal = PokemonGlobalMetadata.new
$game_map = Game_Map.new(1)
$game_map.display_x = 40 * 4
renderer = Atmosphere::Renderer.new(Spriteset_Map.viewport)
renderer.update
views = renderer.instance_variable_get(:@views).values
plane = views.find { |v| v.layer.name == "plane" }.instance_variable_get(:@sprite)
anim = views.find { |v| v.layer.name == "anim" }.instance_variable_get(:@sprite)
still = views.find { |v| v.layer.name == "still" }.instance_variable_get(:@sprite)
check("repeating layer is a plane", plane.is_a?(Plane))
check("one-direction layer is a sprite", anim.is_a?(Sprite) && !anim.is_a?(Plane))
check("plane follows the world camera", plane.ox == 10 * 16 + 40)
check("parallax y", plane.oy == 0)
check("above layers on the map viewport", plane.viewport.equal?(Spriteset_Map.viewport) && plane.z >= 3000)
check("below layers behind the map", !anim.viewport.equal?(Spriteset_Map.viewport))
check("strip wraps within one frame width", anim.x == -((10 * 16 + 40) % 64))
check("still layer moves with the camera", still.x == -(10 * 16 + 40))
check("missing and huge graphics are skipped", ($echo || []).length == 2)
frame0 = anim.bitmap
System.now = 0.3
renderer.update
check("animation advances", !anim.bitmap.equal?(frame0))

m = Atmosphere.manager
m.set(:plane, opacity: 0)
renderer.update
check("invisible layers are hidden", plane.visible == false)
m.set(:plane, opacity: 50)
renderer.update
check("opacity applied", plane.visible && plane.opacity == 50)

$game_map = Game_Map.new(2)
System.now = 1.0
renderer.update
check("cross-fade keeps old sprites while fading", Sprite.live > 1)
System.now = 3.0
renderer.update
renderer.update
check("old group's sprites are disposed", renderer.instance_variable_get(:@views).length == 1)
renderer.dispose
check("all sprites disposed", Sprite.live == 0)
check("all bitmaps released", Bitmap.live == 0)
puts($failures == 0 ? "ok" : "#{$failures} failures")
exit($failures == 0 ? 0 : 1)
