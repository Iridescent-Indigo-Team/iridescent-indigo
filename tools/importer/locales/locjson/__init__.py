"""@package locjson
CSV localization for Pokessentials: gathers the English text of the game
(src/pbs JSON, script _INTL literals, RMXP event text), keeps one CSV per
domain for each language in src/assets/locales/<lang>/, validates the
translations and compiles them into the Marshal'd message files the engine
loads (Data/messages_<lang>_core.dat and Data/messages_<lang>_game.dat).

Everything here is plain Python 3 with no third-party packages. The RMXP map
data and the Marshal output are handled by two small plain-Ruby helpers
(extract_events.rb and write_messages.rb).
"""
