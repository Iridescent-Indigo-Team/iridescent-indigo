"""@package locjson.messages
The engine's message tables (MessageTypes in 003_Intl_Messages.rb) and its
key normalisation.
"""

import re

EVENT_TEXTS = 0
SPECIES_NAMES = 1
SPECIES_CATEGORIES = 2
POKEDEX_ENTRIES = 3
SPECIES_FORM_NAMES = 4
MOVE_NAMES = 5
MOVE_DESCRIPTIONS = 6
ITEM_NAMES = 7
ITEM_NAME_PLURALS = 8
ITEM_DESCRIPTIONS = 9
ABILITY_NAMES = 10
ABILITY_DESCRIPTIONS = 11
TYPE_NAMES = 12
TRAINER_TYPE_NAMES = 13
TRAINER_NAMES = 14
FRONTIER_INTRO_SPEECHES = 15
FRONTIER_END_SPEECHES_WIN = 16
FRONTIER_END_SPEECHES_LOSE = 17
REGION_NAMES = 18
REGION_LOCATION_NAMES = 19
REGION_LOCATION_DESCRIPTIONS = 20
MAP_NAMES = 21
PHONE_MESSAGES = 22
TRAINER_SPEECHES_LOSE = 23
SCRIPT_TEXTS = 24
RIBBON_NAMES = 25
RIBBON_DESCRIPTIONS = 26
STORAGE_CREATOR_NAME = 27
ITEM_PORTION_NAMES = 28
ITEM_PORTION_NAME_PLURALS = 29
POKEMON_NICKNAMES = 30
RIBBON_TITLES = 31
## Not a text table: the language's grammar and number settings
## (MessageTypes::LOCALE_DATA in the engine).
LOCALE_DATA = 99

## Ruby's \s.
_WS = r"[ \t\r\n\f\v]"
_NEEDS_KEY = re.compile(r"[\r\n\t\x01]|^%s+|%s+$|%s{2,}" % (_WS, _WS, _WS), re.M)


def string_to_key(text):
    """Translation.stringToKey: the key the engine looks a string up by.

    Ruby's ^ and $ match at every line, so leading and trailing whitespace of
    every line is removed, and runs of 2+ whitespace become one space.
    """
    if text and _NEEDS_KEY.search(text):
        key = re.sub(r"^%s+" % _WS, "", text, flags=re.M)
        key = re.sub(r"%s+$" % _WS, "", key, flags=re.M)
        key = re.sub(r"%s{2,}" % _WS, " ", key)
        return key
    return text
