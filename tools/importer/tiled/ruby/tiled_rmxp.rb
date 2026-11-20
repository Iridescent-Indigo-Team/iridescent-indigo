#===============================================================================
# tiled_rmxp.rb
#-------------------------------------------------------------------------------
# Shared Ruby support for the Tiled tools (tools/importer/tiled). Required by
# rxdata_export.rb (importer) and rxdata_build.rb (compiler); not run directly.
#
# Provides:
#   * the pure-Ruby RGSS/RPG classes from lib/eevee, so .rxdata files can be
#     loaded and dumped with plain `ruby` (no engine);
#   * TiledRmxp::Dumper, which writes event commands as readable Ruby (the
#     eevee format), falling back to a lossless raw form for any page that the
#     readable form can't reproduce exactly;
#   * TiledRmxp::Factory, which evaluates those files back into RPG objects and
#     adds the Pokessentials helpers (named transfers, raw commands, pages);
#   * helpers to convert RPG objects to and from plain JSON values.
#
# Everything here runs at build time on the developer's machine; nothing is
# needed at runtime, so Android builds are unaffected.
#===============================================================================
require "json"
require "fileutils"

# Event text is UTF-8 whatever the system locale, so `inspect` writes
# "Pokédex" rather than "Pok\u00E9dex" in the event files.
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

module TiledRmxp
  ## Repository root.
  ROOT = File.expand_path("../../../..", __dir__)
end

require File.join(TiledRmxp::ROOT, "lib/eevee/rmxp/rgss")
require File.join(TiledRmxp::ROOT, "tools/scripts/halve_data")

module TiledRmxp
  ## RMXP event command codes that end a page or block.
  END_CODE = 0

  module_function

  # Forces a string read from RMXP data to UTF-8.
  # @param str [String]
  # @return [String]
  def utf8(str)
    return str unless str.is_a?(String)
    s = str.dup.force_encoding("UTF-8")
    return s.valid_encoding? ? s : str.dup.force_encoding("ISO-8859-1").encode("UTF-8")
  end

  # A deep copy of RPG data with every string converted to UTF-8 (RMXP stores
  # them as binary), so dumped Ruby shows "Pokédex" rather than escapes.
  # @param obj [Object]
  # @return [Object]
  def utf8_copy(obj)
    copy = Marshal.load(Marshal.dump(obj))
    seen = {}
    walk = lambda do |o|
      next if seen[o.object_id]
      seen[o.object_id] = true
      case o
      when String then o.replace(utf8(o)) unless o.frozen?
      when Array then o.each { |x| walk.call(x) }
      when Hash then o.each_value { |x| walk.call(x) }
      when Numeric, Symbol, true, false, nil then nil
      else o.instance_variables.each { |iv| walk.call(o.instance_variable_get(iv)) }
      end
    end
    walk.call(copy)
    return copy
  end

  # Loads a Marshal file.
  # @param path [String]
  # @return [Object]
  def load(path)
    return Marshal.load(File.binread(path))
  end

  # Writes a Marshal dump only if its bytes differ from the existing file.
  # @param obj [Object]
  # @param path [String]
  # @return [Boolean] true if the file was written
  def dump_if_changed(obj, path)
    bytes = Marshal.dump(obj)
    return false if File.file?(path) && File.binread(path) == bytes
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path + ".tmp", bytes)
    File.rename(path + ".tmp", path)
    return true
  end

  # A comparable form of an RPG object that ignores data the game never reads
  # (ids of disabled page conditions). Used to check round trips.
  # @param obj [Object]
  # @return [Object] nested arrays, strings and numbers
  def norm(obj)
    case obj
    when String then utf8(obj)
    when Array then obj.map { |x| norm(x) }
    when Hash then obj.keys.sort_by(&:to_s).map { |k| [k, norm(obj[k])] }
    when Numeric, Symbol, true, false, nil then obj
    when Table then [:table, obj.xsize, obj.ysize, obj.zsize, obj.data]
    when RPG::Event::Page::Condition
      c = obj.clone
      c.switch1_id = 1 unless c.switch1_valid
      c.switch2_id = 1 unless c.switch2_valid
      unless c.variable_valid
        c.variable_id = 1
        c.variable_value = 0
      end
      c.self_switch_ch = "A" unless c.self_switch_valid
      return [obj.class.name] + c.instance_variables.sort.map { |iv| [iv, norm(c.instance_variable_get(iv))] }
    else
      [obj.class.name] + obj.instance_variables.sort.map { |iv| [iv, norm(obj.instance_variable_get(iv))] }
    end
  end

  # Converts an RPG object into plain JSON values ({"_class" => ..., ivars}).
  # @param obj [Object]
  # @return [Object]
  def to_json_value(obj)
    case obj
    when String then utf8(obj)
    when Array then obj.map { |x| to_json_value(x) }
    when Hash then obj.to_h { |k, v| [k.to_s, to_json_value(v)] }
    when Numeric, true, false, nil then obj
    when Symbol then { "_symbol" => obj.to_s }
    when Table then { "_class" => "Table", "x" => obj.xsize, "y" => obj.ysize, "z" => obj.zsize, "data" => obj.data }
    when Color then { "_class" => "Color", "v" => [obj.red, obj.green, obj.blue, obj.alpha] }
    when Tone then { "_class" => "Tone", "v" => [obj.red, obj.green, obj.blue, obj.gray] }
    else
      h = { "_class" => obj.class.name }
      obj.instance_variables.each { |iv| h[iv.to_s.delete("@")] = to_json_value(obj.instance_variable_get(iv)) }
      h
    end
  end

  # Inverse of to_json_value.
  # @param value [Object]
  # @return [Object]
  def from_json_value(value)
    case value
    when Array then value.map { |x| from_json_value(x) }
    when Hash
      return value["_symbol"].to_sym if value.key?("_symbol")
      klass = value["_class"]
      return value.to_h { |k, v| [k, from_json_value(v)] } unless klass
      case klass
      when "Table"
        t = Table.new(value["x"], value["y"], value["z"])
        t.data = value["data"]
        return t
      when "Color" then return Color.new(*value["v"])
      when "Tone" then return Tone.new(*value["v"])
      end
      cls = klass.split("::").inject(Object) { |m, c| m.const_get(c) }
      obj = cls.allocate
      value.each do |k, v|
        next if k == "_class"
        obj.instance_variable_set("@#{k}", from_json_value(v))
      end
      obj
    else value
    end
  end

  #=============================================================================
  # Writes event commands as Ruby source.
  #=============================================================================
  class Dumper < RPGDumper
    def initialize
      super(name: "tiled", maps: {})
    end

    # eevee's version pops the route's terminator in place, which breaks routes
    # that Marshal shares between commands; work on a copy instead.
    def command_move_route(command, level)
      copy = command.clone
      route = command.parameters[1].clone
      route.list = route.list.dup
      copy.parameters = [command.parameters[0], route]
      return super(copy, level)
    end

    # Non-mutating version of eevee's route().
    def route(route, level)
      copy = route.clone
      copy.list = route.list.dup
      return super(copy, level)
    end

    # The Ruby literal for one raw command parameter.
    # @param value [Object]
    # @return [String]
    def lit(value)
      case value
      when String then TiledRmxp.utf8(value).inspect
      when nil, true, false, Integer, Float, Symbol then value.inspect
      when Array then "[" + value.map { |v| lit(v) }.join(", ") + "]"
      when RPG::AudioFile then "audio(name: #{lit(value.name)}, volume: #{value.volume}, pitch: #{value.pitch})"
      when Tone then "tone(#{value.red}, #{value.green}, #{value.blue}, #{value.gray})"
      when Color then "color(#{value.red}, #{value.green}, #{value.blue}, #{value.alpha})"
      when RPG::MoveCommand then "mv(" + ([value.code] + value.parameters).map { |v| lit(v) }.join(", ") + ")"
      when RPG::MoveRoute
        "route_raw(#{value.repeat.inspect}, #{value.skippable.inspect}, [" +
          value.list.map { |m| lit(m) }.join(", ") + "])"
      else
        raise "can't write a #{value.class} event parameter"
      end
    end

    # A command list (without its terminator) in the raw form.
    # @param list [Array<RPG::EventCommand>]
    # @param level [Integer] indent level
    # @return [String]
    def raw_list(list, level)
      out = "[\n"
      list.each do |c|
        args = [c.code, c.indent] + c.parameters
        out += indent(level + 1) + "raw(" + args.map { |a| lit(a) }.join(", ") + "),\n"
      end
      return out + indent(level) + "]"
    end

    # A command list (without its terminator) in eevee's readable form.
    def pretty_list(list, level)
      return "[]" if list.empty?
      return "[\n" + command_list(list, level + 1) + indent(level) + "]"
    end

    # The source of a command list: readable if it round-trips exactly,
    # otherwise raw.
    # @param list [Array<RPG::EventCommand>] including the terminator
    # @param level [Integer]
    # @return [String]
    def list_source(list, level = 0)
      body = list[0...-1]
      unless list.last && list.last.code == END_CODE && list.last.indent == 0
        body = list
      end
      begin
        # eevee's dumper changes the commands it prints, so give it a copy.
        text = pretty_list(Marshal.load(Marshal.dump(body)), level)
        back = Factory.new.instance_eval(text).flatten
        return text if TiledRmxp.norm(back) == TiledRmxp.norm(body)
      rescue StandardError, ScriptError
        # fall through to the raw form
      end
      return raw_list(body, level)
    end

    # The source of a custom move route.
    # @param route [RPG::MoveRoute]
    # @return [String]
    def route_source(route)
      begin
        text = route(Marshal.load(Marshal.dump(route)), 0)
        back = Factory.new.instance_eval(text)
        return text if TiledRmxp.norm(back) == TiledRmxp.norm(route)
      rescue StandardError, ScriptError
      end
      return lit(route)
    end

    # The .rb file of a map event: the commands (and custom move routes) of
    # each page. Page settings live on the Tiled object.
    # @param event [RPG::Event]
    # @param title [String] first comment line
    # @return [String]
    def event_file(event, title)
      event = TiledRmxp.utf8_copy(event)
      out = "# #{title}\n"
      out += "# Page settings (conditions, graphic, trigger, movement) are on the event's\n"
      out += "# object in Tiled. See docs/TILED.md for the commands.\n"
      event.pages.each_with_index do |page, i|
        out += "\npage #{i}, " + list_source(page.list) + "\n"
        if page.move_type == 3 || !objects_equal?(page.move_route, RPGDumper::DEFAULT_ROUTE)
          out += "move_route #{i}, " + route_source(page.move_route) + "\n"
        end
      end
      return out
    end

    # The .rb file of a common event.
    # @param event [RPG::CommonEvent]
    # @return [String]
    def common_event_file(event)
      event = TiledRmxp.utf8_copy(event)
      out = "# Common event #{event.id}: #{TiledRmxp.utf8(event.name)}\n"
      out += "common(\n"
      out += "  id: #{event.id},\n"
      out += "  name: #{TiledRmxp.utf8(event.name).inspect},\n"
      out += "  trigger: #{RPGFactory::COMMON_EVENT_TRIGGER[event.trigger].inspect},\n"
      out += "  switch: #{event.switch_id},\n"
      out += "  commands: " + list_source(event.list, 1) + ",\n"
      out += ")\n"
      return out
    end
  end

  #=============================================================================
  # Evaluates event .rb files.
  #=============================================================================
  class Factory < RPGFactory
    ## Commands per page index, set by `page n, [...]`.
    attr_reader :pages
    ## Custom move routes per page index.
    attr_reader :routes
    ## Common event built by `common(...)`.
    attr_reader :common_event

    # @param resolver [Proc, nil] called with (map, spawn) for named transfers;
    #   returns [map_id, x, y, direction] or raises
    # @param params [Hash] the event object's custom properties (template
    #   parameters), read with param()
    def initialize(resolver = nil, params = {})
      super()
      @resolver = resolver
      @params = params || {}
      @pages = {}
      @routes = {}
    end

    # A parameter of the event (a custom property on its Tiled object), e.g.
    # the item of an item ball placed from a template.
    # @param name [Symbol, String]
    # @param default [Object] used when the property isn't set; without a
    #   default, a missing parameter is an error
    def param(name, *default)
      key = name.to_s
      return @params[key] if @params.key?(key) && @params[key] != ""
      return default[0] unless default.empty?
      raise ArgumentError, "this event needs a #{key.inspect} property (template parameter)"
    end

    # Evaluates a file, reporting errors with its name and line.
    # @param path [String]
    # @return [self]
    def run_file(path)
      instance_eval(File.read(path, encoding: "UTF-8"), path, 1)
      return self
    end

    # `page 0, [commands]` records a page's commands; `page(...)` with keyword
    # arguments is eevee's full page constructor.
    def page(*args, **kwargs)
      if args[0].is_a?(Integer)
        @pages[args[0]] = (args[1] || []).flatten
        return nil
      end
      return super(**kwargs)
    end

    # `move_route 0, route(...)` records a page's custom move route.
    def move_route(*args, **kwargs)
      if args[0].is_a?(Integer) && args[1].is_a?(RPG::MoveRoute)
        @routes[args[0]] = args[1]
        return nil
      end
      return super(*args, **kwargs)
    end

    # A common event.
    def common(id:, name: "", trigger: :none, switch: 1, commands: [])
      ev = RPG::CommonEvent.new
      ev.id = id
      ev.name = name
      ev.trigger = COMMON_EVENT_TRIGGER_INVERSE[trigger] || 0
      ev.switch_id = switch
      ev.list = commands.flatten + [RPG::EventCommand.new]
      @common_event = ev
      return ev
    end

    # One command exactly as stored (code, indent, parameters).
    def raw(code, indent, *params)
      return RPG::EventCommand.new(code, indent, params)
    end

    # A move route exactly as stored.
    def route_raw(repeat, skippable, list)
      r = RPG::MoveRoute.new
      r.repeat = repeat
      r.skippable = skippable
      r.list = list
      return r
    end

    # One move route command exactly as stored.
    def mv(code, *params)
      m = RPG::MoveCommand.new
      m.code = code
      m.parameters = params
      return m
    end

    # Changes an atmosphere layer (fog, panorama, ...) from an event: a Script
    # command calling pbAtmosphere.set. See docs/TILED.md#atmospheres.
    # @param layer [Symbol, String] layer name
    # @param changes [Hash] settings, plus frames: (duration) and persist:
    def atmosphere(layer, **changes)
      args = changes.map { |k, v| "#{k}: #{v.inspect}" }
      return script("pbAtmosphere.set(#{layer.to_sym.inspect}#{args.empty? ? '' : ', ' + args.join(', ')})")
    end

    # Transfer Player to a named Spawn object (or tile) of another map.
    # @param to [String, Integer] map name (from the registry) or id
    # @param spawn [String, nil] name of a Spawn object in that map
    # @param x [Integer, nil] tile x, when spawn isn't given
    # @param y [Integer, nil]
    # @param direction [Symbol, nil] :retain, :down, :left, :right, :up; the
    #   spawn's direction when nil
    # @param fading [Boolean]
    def transfer(to:, spawn: nil, x: nil, y: nil, direction: nil, fading: true)
      raise ArgumentError, "transfer needs spawn: or x: and y:" if spawn.nil? && (x.nil? || y.nil?)
      raise "named transfers need the map registry (run through the compiler)" unless @resolver
      map_id, sx, sy, sdir = @resolver.call(to, spawn)
      sx, sy = x, y if spawn.nil?
      dir = direction.nil? ? (sdir || :retain) : direction
      return transfer_player(map: map_id, x: sx, y: sy, direction: dir, fading: fading)
    end
  end
end
