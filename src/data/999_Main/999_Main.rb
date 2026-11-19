class Scene_DebugIntro
  def main
    Graphics.transition(0)
    sscene = PokemonLoad_Scene.new
    sscreen = PokemonLoadScreen.new(sscene)
    sscreen.pbStartLoadScreen
    Graphics.freeze
  end
end

def pbCallTitle
  return Scene_DebugIntro.new if $DEBUG
  return Scene_Intro.new
end

def mainFunction
  if $DEBUG
    pbCriticalCode { mainFunctionDebug }
  else
    mainFunctionDebug
  end
  return 1
end

# Compiles the game data and quits, without opening the game. Used by
# `make compile` (./game.sh --compile) to produce Data/*.dat for builds that
# can't compile at runtime, such as Android. Errors are printed to the console
# instead of message boxes so a headless run never hangs.
def pbCompileOnlyAndExit
  # Send messages that would open a message box to the console instead.
  Object.send(:define_method, :pbPrintException) do |e|
    $stdout.puts("#{e.class}: #{e.message}")
    $stdout.puts(e.backtrace.join("\n")) if e.backtrace
  end
  Object.send(:define_method, :print) { |*args| $stdout.puts(args.join) }
  begin
    $full_compile = true
    PluginManager.runPlugins
    Compiler.main
    File.open(".compile_ok", "wb") { |f| f.write("ok") }
    Kernel.exit!(0)
  rescue Exception => e
    raise if e.is_a?(SystemExit)
    $stdout.puts("Compiling failed: #{e.class}: #{e.message}")
    $stdout.puts(e.backtrace.join("\n")) if e.backtrace
    $stdout.flush
    Kernel.exit!(1)
  end
end

# Writes the PBS schemas of all GameData classes to a JSON file and quits. Used
# by `make pbs-schema` (./game.sh --dump-schema) for the PBS <-> JSON converter
# in tools/importer/pbs.
def pbDumpSchemaAndExit(path)
  begin
    PluginManager.runPlugins
    Compiler.dump_pbs_schema(path)
    File.open(".dump_ok", "wb") { |f| f.write("ok") }
    Kernel.exit!(0)
  rescue Exception => e
    raise if e.is_a?(SystemExit)
    $stdout.puts("Dumping the PBS schema failed: #{e.class}: #{e.message}")
    $stdout.puts(e.backtrace.join("\n")) if e.backtrace
    $stdout.flush
    Kernel.exit!(1)
  end
end

def mainFunctionDebug
  begin
    MessageTypes.load_default_messages if FileTest.exist?("Data/messages_core.dat")
    pbDumpSchemaAndExit(ENV["POKESSENTIALS_DUMP_SCHEMA"]) if !nil_or_empty?(ENV["POKESSENTIALS_DUMP_SCHEMA"])
    pbCompileOnlyAndExit if ENV["POKESSENTIALS_COMPILE_ONLY"] == "1"
    if $DEBUG && !FileTest.exist?("Game.rgssad") && Settings::PROMPT_TO_COMPILE
      pbSetResizeFactor(2)   # Needed to make the message look good (3x)
      if pbConfirmMessage("\\ts[]" + "Do you want to compile your data and plugins?")
        $full_compile = true
      end
    end
    PluginManager.runPlugins
    Compiler.main
    Game.initialize
    Game.set_up_system
    Graphics.update
    Graphics.freeze
    $scene = pbCallTitle
    $scene.main until $scene.nil?
    Graphics.transition
  rescue Hangup
    pbPrintException($!) if !$DEBUG
    pbEmergencySave
    raise
  end
end

loop do
  retval = mainFunction
  case retval
  when 0   # failed
    loop do
      Graphics.update
    end
  when 1   # ended successfully
    break
  end
end
