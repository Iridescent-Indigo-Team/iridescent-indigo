#!/usr/bin/env ruby
#===============================================================================
# extract_events.rb DATA_DIR [--compiled]
#-------------------------------------------------------------------------------
# Prints, as JSON on stdout, every translatable string in the RMXP event data
# of DATA_DIR (MapInfos.rxdata, Map*.rxdata, CommonEvents.rxdata):
#   * Show Text (101 + 401 continuation lines), joined the way the
#     interpreter's command_101 joins them at runtime
#   * Show Choices (102) options
#   * _I("...") literals in Script (355/655), Conditional Branch script (111)
#     and Set Move Route script steps (209)
# Runtime looks event text up by map id + the normalised English text
# (Translation.stringToKey), so that text is what matters, not the key.
#
# Unless --compiled is given, the data is treated as RMXP source data, and the
# Show Text fixes the Essentials compiler applies at compile time are
# replayed first (Compiler.fix_event_use: format code fixes, 4-line splits,
# short-line merges and sentence re-splits; Compiler.convert_to_trainer_event:
# trainer comment events). With --compiled the data is already what the game
# runs (build/Data after `make compile`), so it is read as is.
#
# Output: {"maps": {"<id>": "<name>"}, "texts": [{"map": int, "event": int,
#          "page": int, "command": int, "choice": int|null, "kind": str,
#          "text": str}]}
# Map 0 is the common events (event = common event id, page = 0).
#===============================================================================
require "json"

ROOT = File.expand_path("../../..", __dir__)
require File.join(ROOT, "lib/eevee/rmxp/rgss_internal")
require File.join(ROOT, "lib/eevee/rmxp/rgss_rpg")

module ExtractEvents
  # PBMoveRoute::SCRIPT in Essentials.
  MOVE_ROUTE_SCRIPT = 45
  # Trainer comment keywords (Compiler.convert_to_trainer_event).
  TRAINER_COMMENT = /^(Battle\:|Type\:|Name\:|BattleID\:|DoubleBattle\:|Backdrop\:|EndSpeech\:|Outcome\:|Continue\:|EndBattle\:|EndIfSwitch\:|VanishIfSwitch\:|RegSpeech\:)/i

  module_function

  # @param path [String]
  # @return [Object] the unmarshalled file
  def load(path)
    File.open(path, "rb") { |f| Marshal.load(f) }
  end

  # Forces every String inside an object to UTF-8 (RMXP data is binary).
  # @param obj [Object]
  def utf8(obj)
    case obj
    when String then obj.dup.force_encoding(Encoding::UTF_8)
    when Array  then obj.map { |o| utf8(o) }
    else obj
    end
  end

  # Finds _I("...") literals in event script text, like
  # Translator.find_translatable_text_from_event_script.
  # @param script [String]
  # @return [Array<String>]
  def event_script_texts(script)
    ret = []
    return ret if !script.is_a?(String)
    utf8(script).scan(/(?:_I)\s*\(\s*\"((?:[^\\\"]*\\\"?)*[^\"]*)\"/) do |s|
      string = s[0].dup
      string.gsub!(/\\\"/, "\"")
      string.gsub!(/\\\\/, "\\")
      ret.push(string)
    end
    ret
  end

  #-----------------------------------------------------------------------------
  # Compile-time fixes (source data only)
  #-----------------------------------------------------------------------------

  # Compiler.push_text: splits text at \m into Show Text commands.
  def push_text(list, text, indent = 0)
    return if !text
    text.split(/\\m/).each do |t|
      first = true
      t.split(/\n/).each do |line|
        chunk = line.gsub(/\s+$/, "")
        next if chunk == ""
        list.push(RPG::EventCommand.new(first ? 101 : 401, indent, [chunk]))
        first = false
      end
    end
  end

  # The text-relevant part of Compiler.convert_to_trainer_event: the Show Text
  # and Show Choices commands a trainer comment event is turned into.
  # @param event [RPG::Event]
  # @return [Array<RPG::EventCommand>, nil] nil if it isn't a trainer event
  def trainer_event_list(event)
    return nil if !event || event.pages.length == 0
    list = event.pages[0].list
    return nil if list.length < 2
    commands = []
    list.length.times do |i|
      next if list[i].code != 108
      command = utf8(list[i].parameters[0])
      ((i + 1)...list.length).each do |j|
        break if list[j].code != 408
        command += "\r\n" + utf8(list[j].parameters[0])
      end
      commands.push(command) if command[TRAINER_COMMENT]
    end
    return nil if commands.empty?
    battles = []
    endbattles = []
    regspeech = nil
    commands.each do |command|
      if command[/^Battle\:\s*([\s\S]+)$/i]
        battles.push($~[1])
      elsif command[/^EndBattle\:\s*([\s\S]+)$/i]
        endbattles.push($~[1].gsub(/^\s+/, "").gsub(/\s+$/, ""))
      elsif command[/^RegSpeech\:\s*([\s\S]+)$/i]
        regspeech = $~[1].gsub(/^\s+/, "").gsub(/\s+$/, "")
      end
    end
    return nil if battles.empty?
    endbattles.push("...") if endbattles.empty?
    ret = []
    battles.each { |b| push_text(ret, b); ret.push(RPG::EventCommand.new(0, 0, [])) }
    endbattles.each { |b| push_text(ret, b); ret.push(RPG::EventCommand.new(0, 0, [])) }
    if battles.length > 1
      push_text(ret, regspeech)
      ret.push(RPG::EventCommand.new(102, 0, [["Yes", "No"], 2]))
    end
    ret.push(RPG::EventCommand.new(0, 0, []))
    ret
  end

  # The Show Text (101) part of Compiler.fix_event_use, applied to a copy of an
  # event command list.
  # @param list [Array<RPG::EventCommand>]
  # @return [Array<RPG::EventCommand>]
  def fix_show_text(list)
    list = list.map { |c| RPG::EventCommand.new(c.code, c.indent, utf8(c.parameters)) }
    i = 0
    while i < list.length
      if list[i].code != 101
        i += 1
        next
      end
      if list[i].parameters[0][0, 1] == "\\"
        newx = list[i].parameters[0].clone
        newx.sub!(/^\\[Bb]\s+/, "\\b")
        newx.sub!(/^\\[Rr]\s+/, "\\r")
        newx.sub!(/^\\[Pp][Gg]\s+/, "\\pg")
        newx.sub!(/^\\[Pp][Oo][Gg]\s+/, "\\pog")
        newx.sub!(/^\\[Gg]\s+/, "\\G")
        newx.sub!(/^\\[Cc][Nn]\s+/, "\\CN")
        list[i].parameters[0] = newx
      end
      lines = 1
      j = i + 1
      while j < list.length
        break if list[j].code != 401
        list[j].code = 101 if lines % 4 == 0
        lines += 1
        j += 1
      end
      if lines >= 2 && list[i].parameters[0].length > 0 && list[i].parameters[0].length <= 20 &&
         !list[i].parameters[0][/\\n/]
        list[i].parameters[0] += "\\n" + list[i + 1].parameters[0]
        list.delete_at(i + 1)
        next   # revisit this text command
      elsif lines >= 3 && list[i + lines] && list[i + lines].code == 101
        last_line = list[i + lines - 1].parameters[0].sub(/\s+$/, "")
        if last_line.length > 0 && !last_line[/[\\<]/] && last_line[/[^\.,\!\?\;\-\"]$/]
          message = list[i].parameters[0]
          j = i + 1
          while j < list.length
            break if list[j].code != 401
            message += "\n" + list[j].parameters[0]
            j += 1
          end
          punct = [message.rindex(". "), message.rindex(".\n"),
                   message.rindex("!"), message.rindex("?"), -1].compact.max
          if punct == -1
            punct = [message.rindex(", "), message.rindex(",\n"), -1].compact.max
          end
          if punct != -1
            indent = list[i].indent
            new_message  = message[0, punct + 1].split("\n")
            next_message = message[punct + 1, message.length].sub(/^\s+/, "").split("\n")
            list[i + lines].code = 401
            lines.times { list.delete_at(i) }
            (next_message.length - 1).downto(0) do |k|
              list.insert(i, RPG::EventCommand.new((k == 0) ? 101 : 401, indent, [next_message[k]]))
            end
            (new_message.length - 1).downto(0) do |k|
              list.insert(i, RPG::EventCommand.new((k == 0) ? 101 : 401, indent, [new_message[k]]))
            end
            i += 1
            next
          end
        end
      end
      i += 1
    end
    list
  end

  #-----------------------------------------------------------------------------
  # Extraction
  #-----------------------------------------------------------------------------

  # Collects the texts of one command list.
  # @param list [Array<RPG::EventCommand>]
  # @param base [Hash] map/event/page fields copied into each text
  # @param out [Array<Hash>]
  def collect(list, base, out)
    i = 0
    while i < list.length
      cmd = list[i]
      case cmd.code
      when 101
        start = i
        message = utf8(cmd.parameters[0].to_s)
        while list[i + 1] && list[i + 1].code == 401
          i += 1
          text = utf8(list[i].parameters[0].to_s)
          message += " " if text != "" && message[message.length - 1, 1] != " "
          message += text
        end
        out.push(base.merge("command" => start, "choice" => nil, "kind" => "text", "text" => message))
      when 102
        utf8(cmd.parameters[0]).each_with_index do |choice, k|
          next if !choice.is_a?(String) || choice.empty?
          out.push(base.merge("command" => i, "choice" => k, "kind" => "choice", "text" => choice))
        end
      when 355, 655
        event_script_texts(cmd.parameters[0]).each_with_index do |t, k|
          out.push(base.merge("command" => i, "choice" => k, "kind" => "script", "text" => t))
        end
      when 111
        if cmd.parameters[0] == 12
          event_script_texts(cmd.parameters[1]).each_with_index do |t, k|
            out.push(base.merge("command" => i, "choice" => k, "kind" => "script", "text" => t))
          end
        end
      when 209
        route = cmd.parameters[1]
        if route.respond_to?(:list)
          route.list.each do |step|
            next if step.code != MOVE_ROUTE_SCRIPT
            event_script_texts(step.parameters[0]).each_with_index do |t, k|
              out.push(base.merge("command" => i, "choice" => k, "kind" => "script", "text" => t))
            end
          end
        end
      end
      i += 1
    end
  end

  # @param data_dir [String]
  # @param compiled [Boolean] true if the data was already fixed by the compiler
  # @return [Hash] the JSON document
  def extract(data_dir, compiled)
    texts = []
    maps = {}
    infos_path = File.join(data_dir, "MapInfos.rxdata")
    infos = File.file?(infos_path) ? load(infos_path) : {}
    map_files = Dir.children(data_dir).select { |f| f[/\Amap(\d+)\.rxdata\z/i] }
    ids = map_files.map { |f| f[/\d+/].to_i }.sort
    ids.each do |id|
      file = map_files.find { |f| f[/\d+/].to_i == id }
      map = load(File.join(data_dir, file))
      maps[id.to_s] = infos[id] ? utf8(infos[id].name) : ""
      map.events.keys.sort.each do |event_id|
        event = map.events[event_id]
        trainer = compiled ? nil : trainer_event_list(event)
        if trainer
          collect(fix_show_text(trainer), { "map" => id, "event" => event_id, "page" => 0 }, texts)
          # Other pages are dropped by the conversion; nothing else to read.
          next
        end
        event.pages.each_with_index do |page, page_index|
          list = compiled ? page.list : fix_show_text(page.list)
          collect(list, { "map" => id, "event" => event_id, "page" => page_index }, texts)
        end
      end
    end
    common_path = File.join(data_dir, "CommonEvents.rxdata")
    if File.file?(common_path)
      load(common_path).each_with_index do |ev, index|
        next if !ev || !ev.list
        list = compiled ? ev.list : fix_show_text(ev.list)
        collect(list, { "map" => 0, "event" => index, "page" => 0 }, texts)
      end
    end
    { "maps" => maps, "texts" => texts }
  end
end

if $0 == __FILE__
  args = ARGV.dup
  compiled = !args.delete("--compiled").nil?
  if args.length != 1 || !File.directory?(args[0])
    warn "usage: extract_events.rb DATA_DIR [--compiled]"
    exit 2
  end
  print JSON.generate(ExtractEvents.extract(args[0], compiled))
end
