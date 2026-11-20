#===============================================================================
# atmosphere_test.rb
#-------------------------------------------------------------------------------
# Tests the rules of the runtime Atmosphere::Manager
# (src/data/012_Overworld/001_Overworld visuals/004_Overworld_Atmosphere.rb)
# without the engine: the few engine pieces it uses are stubbed below.
# Run by test_tiled.py (make test-tiled); prints "ok" when every check passes.
#===============================================================================
ROOT = File.expand_path("../../../..", __dir__)

# --- Engine stubs ---------------------------------------------------------------
module System
  @now = 0.0
  class << self
    attr_accessor :now
    def uptime; @now; end
  end
end

module Settings
  ATMOSPHERE_LOW_QUALITY            = false
  ATMOSPHERE_LOW_QUALITY_ON_ANDROID = false
  ATMOSPHERE_MAX_TEXTURE_SIZE       = 4096
  ATMOSPHERE_FADE_FRAMES            = 20
end

class Tone
  attr_reader :red, :green, :blue, :gray
  def initialize(r, g, b, gray = 0); @red, @green, @blue, @gray = r, g, b, gray; end
end

class Game_Map
  TILE_WIDTH = 16
  TILE_HEIGHT = 16
  X_SUBPIXELS = 4
  Y_SUBPIXELS = 4
  attr_accessor :map_id, :tileset_id, :display_x, :display_y, :panorama_name, :panorama_hue,
                :fog_name, :fog_hue, :fog_opacity, :fog_blend_type, :fog_zoom, :fog_sx, :fog_sy
  def initialize(id)
    @map_id = id
    @tileset_id = 1
    @display_x = @display_y = 0
    @panorama_name = @fog_name = ""
    @panorama_hue = @fog_hue = @fog_blend_type = @fog_sx = @fog_sy = 0
    @fog_opacity = 64
    @fog_zoom = 100
  end
end

class PokemonGlobalMetadata; end
class Interpreter
  attr_accessor :parameters
  def command_204; :original; end
end

$atmosphere_data = nil
def pbRgssExists?(_file); !$atmosphere_data.nil?; end
def load_data(_file); Marshal.load(Marshal.dump($atmosphere_data)); end
def nil_or_empty?(s); s.nil? || s.empty?; end
def pbIsAndroid?; false; end
def lerp(start_val, end_val, duration, delta, now = nil)
  return end_val if duration <= 0
  delta = now - delta if now
  return start_val if delta <= 0
  return end_val if delta >= duration
  start_val + ((end_val - start_val) * delta / duration.to_f)
end

load File.join(ROOT, "src/data/012_Overworld/001_Overworld visuals/004_Overworld_Atmosphere.rb")

# --- Helpers ----------------------------------------------------------------------
$failures = 0
def check(label, condition)
  return if condition
  $failures += 1
  puts "FAIL: #{label}"
end

def layer(name, extra = {})
  { "name" => name, "graphic" => "Fogs/#{name}", "z" => "above", "parallax_x" => 1.0, "parallax_y" => 1.0,
    "scroll_x" => 10.0, "scroll_y" => 0.0, "opacity" => 100 }.merge(extra)
end

$atmosphere_data = {
  "groups" => {
    "forest" => { "name" => "Forest", "fade_frames" => 20, "layers" => [layer("mist")] },
    "cave"   => { "name" => "Cave", "fade_frames" => 10, "layers" => [layer("dust", "z" => "below")] }
  },
  "maps" => {
    "1" => { "group" => "forest", "layers" => [] },
    "2" => { "group" => "forest", "layers" => [] },
    "3" => { "group" => "cave", "layers" => [] },
    "4" => { "group" => nil, "layers" => [layer("local")] }
  },
  "world" => { "1" => [0, 0], "2" => [20, 0] }
}
Atmosphere.clear

m = Atmosphere::Manager.new
$game_map = Game_Map.new(1)
m.update
check("forest group loaded", m.key == "group:forest" && m.layer(:mist))
mist = m.layer(:mist)
System.now = 0.1
m.update
check("layers scroll over time", (mist.scroll_pos_x - 1.0).abs < 0.001)
System.now = 5.0
m.update
check("long pauses don't make layers jump", (mist.scroll_pos_x - 3.5).abs < 0.001)

# Continuous across maps of the same group
$game_map = Game_Map.new(2)
m.update
check("same group keeps the same layer objects", m.layer(:mist).equal?(mist))
check("no cross-fade inside a group", m.outgoing.empty?)
$game_map.display_x = 0
check("camera uses the world position", m.camera == [20 * 16, 0])

# Event change: temporary, until leaving the group
m.set(:mist, opacity: 10)
check("set changes the layer", m.layer(:mist)["opacity"] == 10)
$game_map = Game_Map.new(1)
m.update
check("temporary change kept inside the group", m.layer(:mist)["opacity"] == 10)
$game_map = Game_Map.new(3)
System.now = 3.0
m.update
check("cave group loaded", m.key == "group:cave" && m.layer(:dust))
check("cross-fade starts", m.outgoing.key?("mist") && m.layer(:dust).fade == 0.0)
System.now = 3.25
m.update
check("cross-fade halfway", (m.layer(:dust).fade - 0.5).abs < 0.01 && (m.outgoing["mist"].fade - 0.5).abs < 0.01)
System.now = 4.0
m.update
check("cross-fade ends", m.outgoing.empty? && m.layer(:dust).fade == 1.0)
$game_map = Game_Map.new(1)
System.now = 6.0
m.update
check("temporary change undone after leaving the group", m.layer(:mist)["opacity"] == 100)

# Persistent change: reapplied when entering the group again
m.set(:mist, opacity: 33, persist: true)
$game_map = Game_Map.new(3)
System.now = 8.0
m.update
$game_map = Game_Map.new(2)
System.now = 10.0
m.update
check("persistent change reapplied", m.layer(:mist)["opacity"] == 33)
m.reset(persistent: true)
m.update
check("reset(persistent: true) restores the defaults", m.layer(:mist)["opacity"] == 100)

# Gradual change
System.now = 20.0
m.set(:mist, opacity: 0, frames: 20)
System.now = 20.5
m.update
check("tween halfway", (m.layer(:mist)["opacity"] - 50).abs < 0.01)
System.now = 21.5
m.update
check("tween done", m.layer(:mist)["opacity"] == 0)

# Map-only layers, add/remove
$game_map = Game_Map.new(4)
System.now = 30.0
m.update
check("map's own layers", m.key == "map:4" && m.layer(:local))
m.add(:rain, graphic: "Fogs/Rain", opacity: 50)
check("add layer", m.layer(:rain) && m.layer(:rain)["opacity"] == 50)
m.remove(:rain)
check("remove layer", m.layer(:rain).nil?)

# Event commands route to the manager
$PokemonGlobal = PokemonGlobalMetadata.new
$PokemonGlobal.atmosphere = m
interp = Interpreter.new
interp.parameters = [1, "Clouds", 0, 80, 1, 150, 2, 0]
interp.command_204
check("Change Map Settings: fog", m.layer(:fog) && m.layer(:fog)["opacity"] == 80 && m.layer(:fog)["blend"] == 1)
interp.parameters = [40, 0]
interp.command_206
check("Change Fog Opacity", m.layer(:fog)["opacity"] == 40)
interp.parameters = [Tone.new(10, 20, 30, 40), 0]
interp.command_205
check("Change Fog Color Tone", m.layer(:fog)["tone"] == [10, 20, 30, 40])
interp.parameters = [2, "battleback"]
check("other Change Map Settings commands untouched", interp.command_204 == :original)

# Maps without data keep their tileset's fog and panorama
$atmosphere_data = nil
Atmosphere.clear
legacy = Game_Map.new(9)
legacy.fog_name = "Fog"
legacy.panorama_name = "Sky"
$game_map = legacy
m2 = Atmosphere::Manager.new
m2.update
check("legacy fog and panorama", m2.layer(:fog) && m2.layer(:panorama) && m2.layer(:panorama)["z"] == "below")

# Saved with the game
copy = Marshal.load(Marshal.dump(m))
check("manager can be saved", copy.layer(:fog)["opacity"] == 40)

puts($failures == 0 ? "ok" : "#{$failures} failures")
exit($failures == 0 ? 0 : 1)
