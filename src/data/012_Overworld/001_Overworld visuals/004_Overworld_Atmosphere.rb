#===============================================================================
# Atmospheres: fogs, panoramas and any other full-screen layers drawn behind
# or over the map.
#-------------------------------------------------------------------------------
# An atmosphere group (src/tiled/atmospheres/<id>.json) is a list of layers.
# Maps use a group through their "atmosphere" property and can add their own
# layers (image layers in a Tiled "Atmosphere" group). The compiler writes all
# of it to Data/atmospheres.dat, with pixel values already halved for the
# build.
#
# The Atmosphere::Manager owns every effect; maps only tell it which map the
# player is on:
#   * maps in the same group share their layers, so scrolling and animation
#     continue across map transfers;
#   * layers scroll by the camera's position in the world (the Tiled world
#     file), times their x and y parallax, so they stay continuous across
#     connected maps;
#   * moving to a map with another group cross-fades the old layers out and
#     the new ones in;
#   * the rule for changes made by events: a change lasts until the player
#     leaves the current group (or the change is undone), after which the
#     group's defaults come back. `persist: true` also saves the change, and
#     it's reapplied whenever the player enters that group again.
#
# Layers are drawn once, by Atmosphere::Renderer (in Spriteset_Global), not
# once per visible map. See 005_Overworld_AtmosphereRenderer.rb.
#
# Maps without atmosphere data (games still built from RPG Maker XP) keep
# their tileset's fog and panorama, through the same manager.
#===============================================================================
module Atmosphere
  # Compiled atmosphere data.
  DATA_FILE = "Data/atmospheres.dat"
  # Layer names used by the Change Map Settings / Fog event commands.
  PANORAMA = "panorama"
  FOG      = "fog"

  @data = nil

  module_function

  # The compiled data: {"groups" => {}, "maps" => {}, "world" => {}}.
  # @return [Hash]
  def data
    if !@data
      @data = (pbRgssExists?(DATA_FILE) ? load_data(DATA_FILE) : nil) rescue nil
      @data = {} if !@data.is_a?(Hash)
      @data["groups"] ||= {}
      @data["maps"]   ||= {}
      @data["world"]  ||= {}
    end
    return @data
  end

  # Forgets the loaded data (used by F12 soft resets and the debug compiler).
  def clear
    @data = nil
  end

  # @param map_id [Integer]
  # @return [Hash, nil] {"group" => id or nil, "layers" => [...]}
  def map_entry(map_id)
    maps = data["maps"]
    return maps[map_id] || maps[map_id.to_s]
  end

  # @param id [String, Symbol]
  # @return [Hash, nil]
  def group(id)
    return nil if id.nil?
    return data["groups"][id.to_s]
  end

  # The top-left corner of a map in the world, in pixels (build scale).
  # @param map_id [Integer]
  # @return [Array<Integer>]
  def world_origin(map_id)
    pos = data["world"][map_id] || data["world"][map_id.to_s]
    return [0, 0] if !pos
    return [pos[0] * Game_Map::TILE_WIDTH, pos[1] * Game_Map::TILE_HEIGHT]
  end

  # @return [Boolean] true if animation and cross-fades are turned off
  def low_quality?
    return true if Settings::ATMOSPHERE_LOW_QUALITY
    return Settings::ATMOSPHERE_LOW_QUALITY_ON_ANDROID && pbIsAndroid?
  end

  # The manager of the current game.
  # @return [Atmosphere::Manager]
  def manager
    return $PokemonGlobal.atmosphere
  end

  #=============================================================================
  # One layer's settings and state. Plain data, so it can be saved.
  #=============================================================================
  class Layer
    # Settings that can be changed by events, and their defaults.
    DEFAULTS = {
      "graphic"        => "",     # path under Graphics/, without extension
      "z"              => "above",# "below" the map, "above" it, or a number
      "parallax_x"     => 1.0,    # 0 = fixed to the screen, 1 = moves with the map
      "parallax_y"     => 1.0,
      "scroll_x"       => 0.0,    # automatic scrolling, pixels per second
      "scroll_y"       => 0.0,
      "offset_x"       => 0,      # pixels
      "offset_y"       => 0,
      "opacity"        => 255,
      "blend"          => 0,      # 0 normal, 1 add, 2 subtract
      "hue"            => 0,
      "tone"           => [0, 0, 0, 0],
      "zoom_x"         => 100,    # percent
      "zoom_y"         => 100,
      "frames"         => 1,      # animation frames, side by side in the graphic
      "frame_duration" => 5,      # in 1/20ths of a second
      "repeat_x"       => true,
      "repeat_y"       => true,
      "visible"        => true
    }
    # Settings that change gradually when given a duration.
    TWEENABLE = ["opacity", "tone", "offset_x", "offset_y", "zoom_x", "zoom_y"]

    attr_reader :name
    # Scrolled distance so far (pixels).
    attr_accessor :scroll_pos_x, :scroll_pos_y
    # Cross-fade multiplier (0.0-1.0).
    attr_accessor :fade

    # @param name [String]
    # @param settings [Hash]
    def initialize(name, settings = {})
      @name = name.to_s
      @settings = DEFAULTS.merge(Layer.stringify(settings))
      @settings.delete("name")
      @tweens = {}
      @scroll_pos_x = 0.0
      @scroll_pos_y = 0.0
      @fade = 1.0
      @version = 0
    end

    # @param hash [Hash]
    # @return [Hash] the same hash with string keys
    def self.stringify(hash)
      ret = {}
      hash.each { |k, v| ret[k.to_s] = v }
      return ret
    end

    # @param key [String, Symbol]
    def [](key)
      return @settings[key.to_s]
    end

    # Bumped whenever a setting the renderer reads changes.
    # @return [Integer]
    def version
      return @version
    end

    # Changes settings, at once or over a duration.
    # @param changes [Hash]
    # @param seconds [Float] duration of the change (0 = at once)
    def change(changes, seconds = 0)
      Layer.stringify(changes).each do |key, value|
        next if !DEFAULTS.has_key?(key)
        value = [value.red, value.green, value.blue, value.gray] if value.is_a?(Tone)
        if seconds > 0 && TWEENABLE.include?(key)
          @tweens[key] = [@settings[key], value, seconds, System.uptime]
        else
          @tweens.delete(key)
          @settings[key] = value
        end
      end
      @version += 1
    end

    # @return [Hash] a copy of the settings
    def settings
      return @settings.clone
    end

    # Advances scrolling and gradual changes.
    # @param delta [Float] seconds since the last update
    def update(delta)
      @scroll_pos_x += @settings["scroll_x"].to_f * delta
      @scroll_pos_y += @settings["scroll_y"].to_f * delta
      return if @tweens.empty?
      now = System.uptime
      @tweens.each do |key, (from, to, duration, start)|
        if from.is_a?(Array)
          @settings[key] = from.each_with_index.map { |f, i| lerp(f, to[i], duration, start, now) }
        else
          @settings[key] = lerp(from, to, duration, start, now)
        end
      end
      @tweens.delete_if { |_, (_, to, duration, start)| now - start >= duration }
      @version += 1
    end

    # @return [Boolean] true while a gradual change is running
    def tweening?
      return !@tweens.empty?
    end
  end

  #=============================================================================
  # Owns the active layers and every change made to them.
  #=============================================================================
  class Manager
    # Layers being shown (name => Layer), in drawing order.
    attr_reader :layers
    # Layers fading out after a group change.
    attr_reader :outgoing
    # Key of the current group ("group:<id>", "map:<id>" or "legacy:<id>").
    attr_reader :key

    def initialize
      @layers = {}
      @outgoing = {}
      @key = nil
      @map_id = 0
      @persistent = {}     # key => {layer name => changes}, saved
      @temporary = {}      # layer name => changes since entering the group
      @fade_start = nil
      @fade_seconds = 0
      @last_update = nil
    end

    #---------------------------------------------------------------------------
    # Map changes
    #---------------------------------------------------------------------------

    # The group key and layer definitions for a map.
    # @param map [Game_Map]
    # @return [Array] [key, fade seconds, [[name, settings], ...]]
    def definition(map)
      entry = Atmosphere.map_entry(map.map_id)
      if entry.nil?
        return ["legacy:#{map.tileset_id}:#{map.panorama_name}:#{map.fog_name}", 0, legacy_layers(map)]
      end
      list = []
      group = Atmosphere.group(entry["group"])
      (group ? group["layers"] : []).each { |l| list.push([l["name"], l]) }
      (entry["layers"] || []).each { |l| list.push([l["name"], l]) }
      key = entry["group"] ? "group:#{entry['group']}" : "map:#{map.map_id}"
      key += "+map:#{map.map_id}" if entry["group"] && !(entry["layers"] || []).empty?
      frames = (group && group["fade_frames"]) || Settings::ATMOSPHERE_FADE_FRAMES
      return [key, frames / 20.0, list]
    end

    # The tileset's panorama and fog, for maps built from RPG Maker XP.
    # @param map [Game_Map]
    def legacy_layers(map)
      list = []
      if !nil_or_empty?(map.panorama_name)
        list.push([PANORAMA, { "graphic" => "Panoramas/" + map.panorama_name, "hue" => map.panorama_hue,
                               "z" => "below", "parallax_x" => 0.5, "parallax_y" => 0.5 }])
      end
      if !nil_or_empty?(map.fog_name)
        list.push([FOG, { "graphic" => "Fogs/" + map.fog_name, "hue" => map.fog_hue,
                          "opacity" => map.fog_opacity, "blend" => map.fog_blend_type,
                          "zoom_x" => map.fog_zoom, "zoom_y" => map.fog_zoom,
                          "scroll_x" => map.fog_sx * 5, "scroll_y" => map.fog_sy * 5 }])
      end
      return list
    end

    # Called when the player is on a different map.
    # @param map [Game_Map]
    def map_changed(map)
      @map_id = map.map_id
      key, seconds, list = definition(map)
      return if key == @key
      seconds = 0 if Atmosphere.low_quality? || @key.nil?
      @outgoing = (seconds > 0) ? @layers : {}
      @layers = {}
      list.each { |name, settings| @layers[name.to_s] = Layer.new(name, settings) }
      @key = key
      @temporary = {}
      (@persistent[key] || {}).each { |name, changes| apply(name, changes, 0) }
      if seconds > 0
        @fade_start = System.uptime
        @fade_seconds = seconds
        @layers.each_value { |l| l.fade = 0.0 }
      else
        @fade_start = nil
      end
    end

    #---------------------------------------------------------------------------
    # Changes (used by events through pbAtmosphere)
    #---------------------------------------------------------------------------

    # Changes a layer's settings.
    # @param name [String, Symbol] layer name
    # @param frames [Integer] duration in 1/20ths of a second (0 = at once)
    # @param persist [Boolean] also reapply the change when entering this
    #   group again (saved with the game)
    # @param changes [Hash] settings (see Layer::DEFAULTS)
    def set(name, frames: 0, persist: false, **changes)
      name = name.to_s
      record(name, changes, persist)
      apply(name, changes, frames / 20.0)
    end

    # Adds a layer (or replaces one with the same name).
    def add(name, persist: false, **settings)
      name = name.to_s
      record(name, settings.merge("_add" => true), persist)
      @layers[name] = Layer.new(name, settings)
    end

    # Removes a layer.
    def remove(name, persist: false)
      name = name.to_s
      record(name, { "_remove" => true }, persist)
      @layers.delete(name)
    end

    # Undoes this group's changes: temporary ones, and saved ones too if
    # `persistent` is true.
    def reset(persistent: false)
      @persistent.delete(@key) if persistent
      @key = nil      # rebuilds the layers on the next update, without a fade
    end

    # @return [Layer, nil]
    def layer(name)
      return @layers[name.to_s]
    end

    # Applies the Change Map Settings event command (panorama or fog).
    def legacy_command(kind, params)
      if kind == :panorama
        if nil_or_empty?(params[0])
          remove(PANORAMA)
        else
          add(PANORAMA, graphic: "Panoramas/" + params[0], hue: params[1], z: "below",
                        parallax_x: 0.5, parallax_y: 0.5)
        end
      elsif nil_or_empty?(params[0])
        remove(FOG)
      else
        add(FOG, graphic: "Fogs/" + params[0], hue: params[1], opacity: params[2], blend: params[3],
                 zoom_x: params[4], zoom_y: params[4], scroll_x: params[5] * 5, scroll_y: params[6] * 5)
      end
    end

    #---------------------------------------------------------------------------
    # Per frame
    #---------------------------------------------------------------------------

    def update
      map_changed($game_map) if $game_map && ($game_map.map_id != @map_id || @key.nil?)
      now = System.uptime
      delta = @last_update ? [now - @last_update, 0.25].min : 0
      @last_update = now
      @layers.each_value { |l| l.update(delta) }
      @outgoing.each_value { |l| l.update(delta) }
      return if !@fade_start
      t = (@fade_seconds > 0) ? [(now - @fade_start) / @fade_seconds, 1.0].min : 1.0
      @layers.each_value { |l| l.fade = t }
      @outgoing.each_value { |l| l.fade = 1.0 - t }
      return if t < 1.0
      @outgoing = {}
      @fade_start = nil
    end

    # The camera's top-left corner in world pixels.
    # @return [Array<Float>]
    def camera
      return [0, 0] if !$game_map
      origin = Atmosphere.world_origin($game_map.map_id)
      return [origin[0] + ($game_map.display_x / Game_Map::X_SUBPIXELS),
              origin[1] + ($game_map.display_y / Game_Map::Y_SUBPIXELS)]
    end

    #---------------------------------------------------------------------------

    private

    def record(name, changes, persist)
      changes = Layer.stringify(changes)
      (@temporary[name] ||= {}).merge!(changes)
      return if !persist
      saved = ((@persistent[@key] ||= {})[name] ||= {})
      saved.clear if changes["_add"] || changes["_remove"]
      saved.merge!(changes)
    end

    def apply(name, changes, seconds)
      changes = Layer.stringify(changes)
      if changes["_remove"]
        @layers.delete(name)
      elsif changes["_add"]
        @layers[name] = Layer.new(name, changes.reject { |k, _| k.start_with?("_") })
      elsif @layers[name]
        @layers[name].change(changes, seconds)
      end
    end
  end

  #=============================================================================
  # The script interface for events: pbAtmosphere.set(:mist, opacity: 0, ...)
  #=============================================================================
  module API
    module_function

    def set(name, **kwargs)
      Atmosphere.manager.set(name, **kwargs)
    end

    def add(name, **kwargs)
      Atmosphere.manager.add(name, **kwargs)
    end

    def remove(name, **kwargs)
      Atmosphere.manager.remove(name, **kwargs)
    end

    def reset(**kwargs)
      Atmosphere.manager.reset(**kwargs)
    end

    def layer(name)
      return Atmosphere.manager.layer(name)
    end
  end
end

# Event script shortcut: pbAtmosphere.set(:mist, opacity: 0, frames: 40).
def pbAtmosphere
  return Atmosphere::API
end

#===============================================================================
# The manager is saved with the game, so changes made by events (and the
# scroll position) survive saving and loading.
#===============================================================================
class PokemonGlobalMetadata
  attr_writer :atmosphere

  def atmosphere
    @atmosphere = Atmosphere::Manager.new if !@atmosphere
    return @atmosphere
  end
end

#===============================================================================
# The fog and panorama event commands go through the manager.
#===============================================================================
class Interpreter
  alias __atmosphere__command_204 command_204 unless method_defined?(:__atmosphere__command_204)

  def command_204
    case @parameters[0]
    when 0
      Atmosphere.manager.legacy_command(:panorama, @parameters[1..2])
      return true
    when 1
      Atmosphere.manager.legacy_command(:fog, @parameters[1..7])
      return true
    end
    return __atmosphere__command_204
  end

  def command_205
    Atmosphere.manager.set(Atmosphere::FOG, tone: @parameters[0], frames: @parameters[1])
    return true
  end

  def command_206
    Atmosphere.manager.set(Atmosphere::FOG, opacity: @parameters[0], frames: @parameters[1])
    return true
  end
end
