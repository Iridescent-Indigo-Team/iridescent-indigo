#===============================================================================
# Writes the PBS schemas of every GameData class (and the values of the enums
# they refer to) to a JSON file. The file is read by the PBS <-> JSON converter
# in tools/importer/pbs, which runs outside the engine.
# Run with `make pbs-schema` (./game.sh --dump-schema).
#===============================================================================
module Compiler
  module_function

  SCHEMA_DUMP_FORMAT = 1

  # PBS files that are compiled without a GameData class.
  EXTRA_PBS_FILES = {
    :Connection     => "map_connections",
    :RegionalDex    => "regional_dexes",
    :BattleFacility => "battle_facility_lists"
  }

  def dump_pbs_schema(path)
    enums = {}
    classes = {}
    GameData.constants.sort_by { |c| c.to_s }.each do |c|
      klass = GameData.const_get(c)
      next if !klass.is_a?(Class) || !klass.const_defined?(:PBS_BASE_FILENAME)
      entry = {
        "pbs_base_filename" => klass::PBS_BASE_FILENAME,
        "data_filename"     => (klass.const_defined?(:DATA_FILENAME)) ? klass::DATA_FILENAME : nil,
        "optional"          => (klass.const_defined?(:OPTIONAL) && klass::OPTIONAL) ? true : false
      }
      if klass == GameData::Species
        entry["schema"] = schema_dump_entries(klass.schema(false), enums)
        entry["form_schema"] = schema_dump_entries(klass.schema(true), enums)
      elsif klass.const_defined?(:SCHEMA)
        entry["schema"] = schema_dump_entries(klass.schema, enums)
      else
        entry["schema"] = nil   # Has its own PBS format (e.g. encounters.txt)
      end
      if klass.respond_to?(:sub_schema)
        entry["sub_schema"] = schema_dump_entries(klass.sub_schema, enums)
      end
      classes[c.to_s] = entry
    end
    # PlayerMetadata has no PBS file of its own; it is in metadata.txt.
    if GameData.const_defined?(:PlayerMetadata) && !classes["PlayerMetadata"]
      classes["PlayerMetadata"] = {
        "pbs_base_filename" => GameData::Metadata::PBS_BASE_FILENAME,
        "data_filename"     => GameData::PlayerMetadata::DATA_FILENAME,
        "optional"          => false,
        "schema"            => schema_dump_entries(GameData::PlayerMetadata.schema, enums)
      }
    end
    # Values of the hardcoded GameData enums referred to by the schemas.
    enum_values = {}
    enums.keys.sort.each do |name|
      klass = GameData.const_get(name.to_sym)
      info = {}
      if klass.const_defined?(:PBS_BASE_FILENAME)
        info["source"] = "pbs"
      else
        info["source"] = "hardcoded"
        info["values"] = schema_dump_enum_ids(klass)
      end
      enum_values[name] = info
    end
    # Extra information needed to check particular fields.
    extra = {}
    if GameData.const_defined?(:Evolution)
      params = {}
      GameData::Evolution.each do |evo|
        params[evo.id.to_s] = (evo.parameter.nil?) ? nil : evo.parameter.to_s
      end
      extra["evolution_parameters"] = params
      enum_values["Evolution"] ||= { "source" => "hardcoded", "values" => schema_dump_enum_ids(GameData::Evolution) }
    end
    if GameData.const_defined?(:EncounterType)
      types = {}
      GameData::EncounterType.each do |enc|
        types[enc.id.to_s] = { "type" => enc.type.to_s, "trigger_chance" => enc.trigger_chance }
      end
      extra["encounter_types"] = types
    end
    ["Stat", "Nature", "Item", "Move", "Species", "TrainerType"].each do |name|
      next if enum_values[name] || !GameData.const_defined?(name.to_sym)
      klass = GameData.const_get(name.to_sym)
      if klass.const_defined?(:PBS_BASE_FILENAME)
        enum_values[name] = { "source" => "pbs" }
      else
        enum_values[name] = { "source" => "hardcoded", "values" => schema_dump_enum_ids(klass) }
      end
    end
    if GameData.const_defined?(:Stat)
      main_stats = []
      GameData::Stat.each_main do |s|
        main_stats.push({ "id" => s.id.to_s, "pbs_order" => s.pbs_order })
      end
      extra["main_stats"] = main_stats
    end
    extra["max_level"] = GameData::GrowthRate.max_level if GameData.const_defined?(:GrowthRate)
    pbs_files = {}
    GameData.get_all_pbs_base_filenames.merge(EXTRA_PBS_FILES).each do |key, base|
      pbs_files[key.to_s] = base
    end
    dump = {
      "format"             => SCHEMA_DUMP_FORMAT,
      "essentials_version" => Essentials::VERSION,
      "pbs_files"          => pbs_files.sort.to_h,
      "classes"            => classes,
      "enums"              => enum_values,
      "extra"              => extra
    }
    File.open(path, "wb") { |f| f.write(schema_dump_json(dump, 0) + "\n") }
  end

  # Converts a schema hash into an array of hashes, keeping its order.
  def schema_dump_entries(schema, enums)
    ret = []
    schema.each do |key, value|
      entry = {
        "key"      => key,
        "property" => value[0].to_s,
        "type"     => value[1]
      }
      refs = []
      (value.length - 2).times { |i| refs.push(schema_dump_enum_ref(value[2 + i], enums)) }
      refs.pop while refs.length > 0 && refs.last.nil?
      entry["enums"] = refs if refs.length > 0
      ret.push(entry)
    end
    return ret
  end

  def schema_dump_enum_ref(enumer, enums)
    case enumer
    when nil
      return nil
    when Symbol, String
      if !Kernel.const_defined?(enumer.to_sym) && GameData.const_defined?(enumer.to_sym)
        enums[enumer.to_s] = true
        return { "gamedata" => enumer.to_s }
      end
      mod = Object.const_get(enumer.to_sym)
      return { "module" => enumer.to_s, "values" => schema_dump_module_constants(mod) }
    when Module
      return { "module" => enumer.name, "values" => schema_dump_module_constants(enumer) }
    when Array
      return { "array" => enumer.map { |v| v.to_s } }
    when Hash
      ret = {}
      enumer.each { |k, v| ret[k.to_s] = v }
      return { "hash" => ret }
    end
    return { "unknown" => enumer.inspect }
  end

  def schema_dump_module_constants(mod)
    ret = {}
    mod.constants.each { |c| ret[c.to_s] = mod.const_get(c) }
    return ret
  end

  def schema_dump_enum_ids(klass)
    return klass::DATA.keys.select { |k| k.is_a?(Symbol) }.map { |k| k.to_s }
  end

  # A small JSON writer, as mkxp-z's Ruby may not include the json library.
  def schema_dump_json(value, indent)
    pad = "  " * indent
    case value
    when Hash
      return "{}" if value.empty?
      lines = value.map do |k, v|
        pad + "  " + schema_dump_json_string(k.to_s) + ": " + schema_dump_json(v, indent + 1)
      end
      return "{\n" + lines.join(",\n") + "\n" + pad + "}"
    when Array
      return "[]" if value.empty?
      if value.all? { |v| !v.is_a?(Hash) && !v.is_a?(Array) }
        return "[" + value.map { |v| schema_dump_json(v, indent + 1) }.join(", ") + "]"
      end
      lines = value.map { |v| pad + "  " + schema_dump_json(v, indent + 1) }
      return "[\n" + lines.join(",\n") + "\n" + pad + "]"
    when String, Symbol
      return schema_dump_json_string(value.to_s)
    when true then return "true"
    when false then return "false"
    when nil then return "null"
    when Integer then return value.to_s
    when Float then return value.to_s
    end
    return schema_dump_json_string(value.inspect)
  end

  def schema_dump_json_string(str)
    ret = str.gsub(/[\\"\u0000-\u001f]/) do |c|
      case c
      when "\\" then "\\\\"
      when "\"" then "\\\""
      when "\n" then "\\n"
      when "\r" then "\\r"
      when "\t" then "\\t"
      else sprintf("\\u%04x", c.ord)
      end
    end
    return "\"" + ret + "\""
  end
end
