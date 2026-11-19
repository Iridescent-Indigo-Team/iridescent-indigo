#===============================================================================
# runtime_smoke.rb GAME_DIR CODE
#-------------------------------------------------------------------------------
# Loads the engine's translation scripts (003_Intl_Messages.rb,
# 003_Intl_Grammar.rb) in plain Ruby, with the few engine functions they need
# stubbed, loads the message files of language CODE from GAME_DIR/Data, then
# reads Ruby expressions from stdin (one per line) and prints each result as
# JSON, one per line. Used by test_locales.py.
#===============================================================================
require "json"

ROOT = File.expand_path("../../../..", __dir__)
Dir.chdir(ARGV[0])

def nil_or_empty?(s)
  return s.nil? || (s.respond_to?(:empty?) && s.empty?)
end

def load_data(path)
  File.open(path, "rb") { |f| Marshal.load(f) }
end

def pbRgssOpen(path, mode, &block)
  File.open(path, mode, &block)
end

class Numeric
  def to_s_formatted
    separator = (defined?(LocaleGrammar)) ? LocaleGrammar.data["thousands"] || "," : ","
    return self.to_s.reverse.gsub(/(\d{3})(?=\d)/) { $1 + separator.reverse }.reverse
  end
end

class FakePlayer
  attr_accessor :female
  def female?; return @female; end
end
$player = FakePlayer.new

load File.join(ROOT, "src/data/001_Technical/003_Intl_Messages.rb")
load File.join(ROOT, "src/data/001_Technical/003_Intl_Grammar.rb")
MessageTypes.load_message_files(ARGV[1])

STDIN.each_line do |line|
  line = line.strip
  next if line.empty?
  begin
    puts JSON.generate([eval(line)])
  rescue StandardError => e
    puts JSON.generate(["ERROR #{e.class}: #{e.message}"])
  end
end
