"""@package locjson.config
Paths and locales.json.
"""

import json
import os

## Folder of the localization tools (tools/importer/locales).
TOOL_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
## The repository root.
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(TOOL_DIR)))
## Default configuration file.
CONFIG_FILE = os.path.join(TOOL_DIR, "locales.json")
## Default folder of the translation CSVs.
LOCALES_DIR = os.path.join(ROOT, "src", "assets", "locales")
## The English game data (JSON).
PBS_DIR = os.path.join(ROOT, "src", "pbs")
## The PBS converter, whose loader reads src/pbs.
PBS_TOOL_DIR = os.path.join(ROOT, "tools", "importer", "pbs")
## Game scripts scanned for _INTL text.
SCRIPT_DIRS = [os.path.join(ROOT, "src", "data"), os.path.join(ROOT, "src", "assets", "plugins")]
## RMXP data with the event text (installed by install_assets.sh).
DATA_DIR = os.path.join(ROOT, "src", "assets", "data")
## English graphics.
GRAPHICS_DIR = os.path.join(ROOT, "src", "assets", "graphics")
## Fonts.
FONTS_DIR = os.path.join(ROOT, "src", "assets", "fonts")
## The event text extractor (Ruby).
EXTRACT_EVENTS = os.path.join(TOOL_DIR, "extract_events.rb")
## The message file writer (Ruby).
WRITE_MESSAGES = os.path.join(TOOL_DIR, "write_messages.rb")
## The folder copier used by the main build.
SYNC_DIR = os.path.join(ROOT, "tools", "scripts", "sync_dir.py")


class Language:
    """One translation language from locales.json."""

    def __init__(self, data, grammar):
        ## Code, also the folder name and the message file fragment ("de").
        self.code = data["code"]
        ## Name shown in the language picker.
        self.name = data["name"]
        ## Pokemon::Owner language id.
        self.owner_language = int(data["owner_language"])
        ## Three-letter tag shown on the Summary screen.
        self.tag = data.get("tag", self.code.upper()[:3])
        ## Plural rule name (one_is_1 or one_is_0_1).
        self.plural = data.get("plural", "one_is_1")
        ## Thousands separator for numbers.
        self.thousands = data.get("thousands", ",")
        ## Gender used for nouns without one.
        self.default_gender = data.get("default_gender", "m")
        ## Genders nouns can have in this language.
        self.genders = list(data.get("genders", ["m", "f", "n"]))
        ## {"articles": {...}, "sounds": {...}}
        self.grammar = grammar or {"articles": {}, "sounds": {}}

    @property
    def articles(self):
        return self.grammar.get("articles", {})

    @property
    def sounds(self):
        return self.grammar.get("sounds", {})


class Config:
    """locales.json."""

    def __init__(self, path=CONFIG_FILE):
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        grammar = data.get("grammar", {})
        ## The translation languages, in picker order.
        self.languages = []
        for lang in data["languages"]:
            g = grammar.get(lang["code"])
            seen = set()
            while g and "same_as" in g and g["same_as"] not in seen:
                seen.add(g["same_as"])
                g = grammar.get(g["same_as"])
            self.languages.append(Language(lang, g))
        ## Message window: font, size, width, lines.
        self.message_box = data["message_box"]
        ## Sample texts for codes (see codes.displayed_text).
        self.samples = data.get("samples", {})
        ## Fixed-size text fields: "file.field" -> box.
        self.fields = data.get("fields", {})
        ## Font for single-line names.
        self.name_font = data.get("name_font", {"font": self.message_box["font"], "size": 16})
        ## Graphic paths known to contain English text.
        self.graphics_with_text = list(data.get("graphics_with_text", []))
        ## Allowed size changes of localized graphics: "lang/path" or "path".
        self.graphics_size_exceptions = set(data.get("graphics_size_exceptions", []))

    def language(self, code):
        for lang in self.languages:
            if lang.code == code:
                return lang
        return None
