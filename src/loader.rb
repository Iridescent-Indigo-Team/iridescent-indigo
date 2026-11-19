#===============================================================================
# Pokessentials script loader
#-------------------------------------------------------------------------------
# mkxp-z runs this file through its "customScript" option (see mkxp.json)
# instead of reading Data/Scripts.rxdata. It loads every .rb file in the
# scripts folder, in the same order Essentials uses for extracted scripts:
#   * inside each folder, files are loaded before subfolders;
#   * files and subfolders are each sorted by name, so the numeric prefixes
#     (001_, 002_, ...) decide the order.
#
# The scripts folder is "Scripts" (relative to the game folder) unless the
# POKESSENTIALS_SCRIPTS environment variable points somewhere else (used by
# `game.sh --live` to run straight from src/data without rebuilding).
#
# Because mkxp-z skips its own script runner when customScript is set, this
# loader also:
#   * fills $RGSS_SCRIPTS like Scripts.rxdata would, since Essentials reads it
#     for translations and error messages;
#   * restarts the scripts when F12 (Reset) is pressed.
#
# This file only uses core Ruby and Zlib, so it also works on Android where
# the pure-Ruby standard library is not bundled.
#===============================================================================
module ScriptLoader
  DEFAULT_SCRIPTS_DIR = "Scripts"

  module_function

  # @return [String] the folder that holds the game scripts.
  def scripts_dir
    dir = ENV["POKESSENTIALS_SCRIPTS"]
    return dir if dir && !dir.empty?
    return DEFAULT_SCRIPTS_DIR
  end

  # Collects every .rb file under dir in load order.
  # @param dir [String] folder to walk
  # @param out [Array<String>] list the paths are appended to
  # @return [Array<String>] out
  def collect(dir, out = [])
    entries = Dir.children(dir).reject { |name| name.start_with?(".") }.sort
    folders = entries.select { |name| File.directory?(File.join(dir, name)) }
    files   = entries - folders
    files.each do |name|
      out.push(File.join(dir, name)) if name.downcase.end_with?(".rb")
    end
    folders.each { |name| collect(File.join(dir, name), out) }
    return out
  end

  # Reads a script as UTF-8 text with Unix line endings.
  # @param path [String]
  # @return [String]
  def read_script(path)
    code = File.binread(path)
    code.force_encoding(Encoding::UTF_8)
    code = code[1..] if code.start_with?("﻿")
    return code.gsub("\r\n", "\n")
  end

  # Builds a $RGSS_SCRIPTS-style list: [id, name, deflated code].
  # @param root [String] scripts folder
  # @param paths [Array<String>]
  # @param codes [Array<String>]
  # @return [Array<Array>]
  def rgss_scripts(root, paths, codes)
    ret = []
    paths.each_with_index do |path, i|
      name = path.sub(/\A#{Regexp.escape(root)}\/?/, "").sub(/\.rb\z/i, "")
      ret.push([i, name, Zlib::Deflate.deflate(codes[i])])
    end
    return ret
  end

  # Runs one script at top level with its own local variable scope, the same
  # way RMXP runs one section of Scripts.rxdata.
  # @param code [String]
  # @param path [String] shown in backtraces
  def run_script(code, path)
    if defined?(RubyVM::InstructionSequence)
      RubyVM::InstructionSequence.compile(code, path, path).eval
    else
      eval(code, TOPLEVEL_BINDING, path)
    end
  end

  # @return [Class, nil] the exception class mkxp-z raises on F12.
  def reset_class
    return RGSSReset if defined?(RGSSReset)
    return Reset if defined?(Reset)
    return nil
  end

  # Clears audio and graphics state after a reset, as mkxp-z would.
  def reset_engine
    Audio.__reset__ if Audio.respond_to?(:__reset__)
    Graphics.__reset__ if Graphics.respond_to?(:__reset__)
  end

  # Loads and runs every script, restarting them after each F12 reset.
  def main
    root = scripts_dir
    if !File.directory?(root)
      msg = "Pokessentials: scripts folder \"#{root}\" was not found.\n" +
            "Build the game with `make` and launch it with ./game.sh."
      print(msg)
      return
    end
    paths = collect(root)
    codes = paths.map { |path| read_script(path) }
    $RGSS_SCRIPTS = rgss_scripts(root, paths, codes)
    loop do
      begin
        paths.each_with_index { |path, i| run_script(codes[i], path) }
        break
      rescue Exception => e
        raise if reset_class.nil? || !e.is_a?(reset_class)
        reset_engine
        GC.start
      end
    end
  end
end

ScriptLoader.main
