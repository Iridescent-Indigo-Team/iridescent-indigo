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
