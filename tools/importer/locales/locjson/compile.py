"""@package locjson.compile
Turns validated translations into the message files the engine loads.

The output has exactly the layout Translation#load_message_files expects
(003_Intl_Messages.rb): a Marshal'd Array indexed by MessageTypes, whose
entries are Hashes from Translation.stringToKey(English) to the translation.
Event text is an Array (index EVENT_TEXTS) of such Hashes by map id (0 =
common events). Script text goes in messages_<lang>_core.dat, the rest in
messages_<lang>_game.dat, together with MessageTypes::LOCALE_DATA: the
grammar tables and noun genders 003a_Intl_Grammar.rb uses.

write_messages.rb does the Marshal part, so the files are written by Ruby
itself.
"""

import json
import os
import subprocess
import tempfile

from . import config as cfg
from . import messages as mt


def locale_data(lang, compiled):
    """The LOCALE_DATA entry: grammar settings and translated noun info."""
    singular = {}
    for s, row in compiled:
        if s.noun and s.number == "sg":
            singular[s.noun] = row
    nouns = {}
    for s, row in compiled:
        if not s.noun:
            continue
        text = row.get_value("translation")
        gender = row.get_value("gender").strip().lower()
        sound = row.get_value("sound").strip().lower()
        base = singular.get(s.noun)
        if not gender and base is not None:
            gender = base.get_value("gender").strip().lower()
        if not sound and base is not None and s.number == "sg":
            sound = base.get_value("sound").strip().lower()
        if sound == "consonant":
            sound = "none"
        nouns[text] = [gender or lang.default_gender, s.number, sound]
    return {
        "code": lang.code,
        "name": lang.name,
        "owner_language": lang.owner_language,
        "tag": lang.tag,
        "plural": lang.plural,
        "thousands": lang.thousands,
        "default_gender": lang.default_gender,
        "articles": lang.articles,
        "sounds": lang.sounds,
        "nouns": nouns,
    }


def message_tables(compiled):
    """@return (core, game, events) as {table: {key: text}} and {map: {key: text}}"""
    core, game, events = {}, {}, {}
    for s, row in compiled:
        text = row.get_value("translation")
        table, map_id, key = s.runtime_key
        if not key:
            continue
        if table == mt.EVENT_TEXTS:
            events.setdefault(map_id, {})[key] = text
        elif table == mt.SCRIPT_TEXTS:
            core.setdefault(table, {})[key] = text
        else:
            game.setdefault(table, {})[key] = text
    return core, game, events


def write_language(lang, compiled, out_dir, ruby="ruby"):
    """Writes Data/messages_<code>_core.dat and _game.dat. @return list of files written"""
    core, game, events = message_tables(compiled)
    doc = {
        "core": {str(k): v for k, v in core.items()},
        "game": {str(k): v for k, v in game.items()},
        "events": {str(k): v for k, v in events.items()},
        "locale": locale_data(lang, compiled),
        "locale_index": mt.LOCALE_DATA,
        "event_index": mt.EVENT_TEXTS,
    }
    os.makedirs(out_dir, exist_ok=True)
    fd, tmp = tempfile.mkstemp(suffix=".json", prefix="locale_")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(doc, f, ensure_ascii=False)
        core_file = os.path.join(out_dir, "messages_%s_core.dat" % lang.code)
        game_file = os.path.join(out_dir, "messages_%s_game.dat" % lang.code)
        proc = subprocess.run([ruby, cfg.WRITE_MESSAGES, tmp, core_file, game_file],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if proc.returncode != 0:
            raise RuntimeError("write_messages.rb failed:\n" + proc.stderr.decode("utf-8", "replace"))
        return [p for p in proc.stdout.decode("utf-8").split("\n") if p]
    finally:
        os.unlink(tmp)
