# Localization (translations as CSV)

Pokessentials keeps every translation as **CSV files**, one folder per language
in `src/assets/locales/`. English stays the source: it comes from the game data
JSON in `src/pbs/`, the `_INTL("...")` text in the scripts and the event text of
the maps. The build checks the translations and **compiles** them into the
message files the engine loads (`Data/messages_<lang>_core.dat` and
`Data/messages_<lang>_game.dat`), so nothing is parsed while the game runs.

- [Languages](#languages)
- [Workflow](#workflow)
- [The CSV files](#the-csv-files)
- [Control codes and placeholders](#control-codes-and-placeholders)
- [Grammar](#grammar)
- [Validation](#validation)
- [Text box sizes](#text-box-sizes)
- [Localized graphics](#localized-graphics)
- [Choosing the language in game](#choosing-the-language-in-game)
- [The language of Pokémon](#the-language-of-pokémon)
- [Adding a language](#adding-a-language)
- [How it works](#how-it-works)

## Languages

| Code | Language | Pokémon language ID | Tag |
| --- | --- | --- | --- |
| `en` | English (source) | 2 | ENG |
| `de` | Deutsch | 5 | GER |
| `fr` | Français | 3 | FRE |
| `it` | Italiano | 4 | ITA |
| `es` | Español (España) | 7 | SPA |
| `es_419` | Español (Latinoamérica) | 11 | SPL |

The language ID is what Pokémon store as their original language (see
[below](#the-language-of-pokémon)). 1–10 are the IDs the official games use;
Latin American Spanish has no official ID, so it uses 11, the first free one.

The languages are configured in two places, which must agree:

- `Settings::LANGUAGES` in `src/data/001_Settings.rb`: what the player can
  choose in game (name, code, language ID).
- `tools/importer/locales/locales.json`: what the tools build, with each
  language's grammar.

## Workflow

```bash
make update-locales
```

Writes the current English text into every language's CSVs. Run it after
changing game data, scripts or maps. It never loses a translation:

- new text gets a new row;
- a row whose English changed is marked `stale`;
- a row whose text no longer exists is marked `obsolete` (or dropped, if it
  was never translated);
- a new row whose English is the same as an existing translated row of the
  same file gets that translation, so moving or renumbering events keeps their
  text.

Event text is read from the maps in `src/assets/data` (installed by
`tools/scripts/install_assets.sh`), or from `build/Data` once the game has been
compiled. Without map data the event CSVs are left as they are.

```bash
make validate-locales
```

Checks the translations and prints a summary for each language. `VERBOSE=1`
lists every warning, `LANGS=de,fr` checks only some languages and `STRICT=1`
fails on warnings too.

```bash
make
```

`make` (and `./game.sh`) validates the translations and compiles them into
`build/Data/`. Errors stop the build; warnings don't. `make locales` does only
this step.

```bash
make test-locales
```

Runs the tools' tests.

## The CSV files

```
src/assets/locales/
  de/
    abilities.csv  battle_facility.csv  items.csv  map_names.csv
    metadata.csv   moves.csv  phone.csv  ribbons.csv  scripts.csv
    species.csv    town_map.csv  trainer_types.csv  trainers.csv  types.csv
    events/
      common_events.csv  map001.csv  map002.csv  ...
    graphics/        (optional, see Localized graphics)
  fr/ ...
```

The files are UTF-8 with a byte order mark, so Excel, LibreOffice and Google
Sheets open them with the right characters. Save them as **CSV UTF-8**.
Standard CSV quoting applies, and the tools write it for you:

- a field with a comma, a quote or a line break is wrapped in double quotes;
- a double quote inside a field is written twice (`""`);
- a **line break inside a field is a line break in game**.

| Column | Who edits it | Meaning |
| --- | --- | --- |
| `key` | tools | Stable name of the text (`POTION.description`, `ev012.p1.c004`). |
| `context` | tools | Where the text is used. "Same text" lists other keys with identical English, which share this row. |
| `english` | tools | The English source, to translate from. |
| `translation` | translator | The translation. Empty means English is shown. |
| `status` | both | Empty, `stale` (the English changed since translating: check the translation, then clear the status) or `obsolete` (the text is gone from the game; kept for reference, never used). |
| `notes` | translator | Free notes. Never used by the game. |
| `gender` | translator | Nouns only: `m`, `f` or `n`. See [Grammar](#grammar). |
| `sound` | translator | Nouns only: `vowel`, `special` or `consonant`, to override how the noun's first sound is guessed. |

You can add your own columns; the tools keep them.

### Keys

| File | Keys |
| --- | --- |
| `species.csv` | `PIKACHU.name`, `.category`, `.pokedex`, `.form_name`; forms are `VENUSAUR_1.form_name` etc. |
| `items.csv` | `POTION.name`, `.name_plural`, `.portion_name`, `.portion_name_plural`, `.description` |
| `moves.csv`, `abilities.csv`, `ribbons.csv` | `ID.name`, `ID.description` |
| `types.csv`, `trainer_types.csv` | `ID.name` |
| `trainers.csv` | `TYPE.Name[.version].name`, `.lose_text`, `.pokemonN.nickname` |
| `map_names.csv` | `MAP003.name` |
| `town_map.csv` | `REGION0.name`, `location.<name>`, `point.<name>` |
| `phone.csv` | `<contact>.<kind>.N` (`\m` in a phone text starts a new message) |
| `battle_facility.csv` | `name.`, `begin_speech.`, `end_speech_win.`, `end_speech_lose.` + a hash of the English |
| `metadata.csv` | `storage_creator` |
| `scripts.csv` | `s.` + a hash of the English; `context` lists the script lines |
| `events/mapNNN.csv` | `evEEE.pP.cCCC` (event, page, command), `.choiceN` for Show Choices options, `.scriptN` for `_I("...")` text in scripts |
| `events/common_events.csv` | `ceEEE.cCCC` |

Event keys follow the compiled event commands, including the compiler's own
fixes (long Show Text commands are split into 4 lines, very short first lines
are merged with `\n`), so they match what the game shows.

### The game looks text up by its English

The engine finds a translation by its English text (in a table such as "item
names" or "map 3's events"), not by key. So text with the same English in the
same table has **one** translation: those rows are merged into one, and the
validator reports two rows that the engine can't tell apart but that are
translated differently. If one English line needs two different translations,
change the English slightly (or move it to another map).

## Control codes and placeholders

Translations must keep the codes of the English. The validator compares them:

| Kind | Codes | If they differ |
| --- | --- | --- |
| Content and flow | `\PN` `\PM` `\v[n]` `\n[n]` `\TN` `\TP` `\TE` `\m` `\G` `\CN` `\PT` `\se[...]` `\me[...]` `\f[...]` `\ff[...]` `\ch[...]` `\cl` `\wd` `\wm` `\wu` `\op` `\^` `\wtnp[n]` `\sign[...]` `<icon=...>` `<img=...>` | error |
| Style | `\c[n]` `\b` `\r` `\pg` `\pog` `\[XXXXXXXX]` `\ts[n]` `\w[...]` `\l[n]` and tags like `<b>` `<i>` `<u>` `<c2=...>` `<ac>` | warning |
| Pauses and breaks | `\n` `\.` `\|` `\wt[n]` `\!` `\1` `<br>` | free: add, move or drop them |

- `{1}`, `{2}`… are filled in by the game. They can be **reordered or
  repeated**; using one the English doesn't have is an error, leaving one out a
  warning.
- `{1:d}`, `{2:05.1f}`… (in `_ISPRINTF` text) must keep their format.
- `\\` is a literal backslash. An unknown code such as `\PX` is an error.
- For `\ch[var,cancel,option1,option2]` the options are text to translate;
  the variable, cancel value and number of options must stay.
- Tags such as `<b>…</b>` must be balanced.
- `&lt;`, `&gt;`, `&amp;`, `&quot;`, `&apos;` are escapes for `<`, `>`, `&`,
  `"`, `'`.

## Grammar

Translations (and English text, too) can use these tokens:

| Token | Result |
| --- | --- |
| `{pg:male|female}` | Chooses by the player's gender: `¿Estás listo{pg:|a}?`, `Tu es prêt{pg:|e} ?` |
| `{1|plural:one|other}` | Chooses by the number in argument 1, with the language's plural rule (French counts 0 as singular). `#` is replaced by the number: `{1|plural:# Pokémon|# Pokémon}` |
| `{1|g:masc|fem|neut}` | Chooses by the gender of the noun in argument 1: `{1|g:Er|Sie|Es} wurde benutzt.` |
| `{1|def}`, `{1|indef}` | The noun in argument 1 with its article: `Du erhältst {1|indef.acc}!` gives "Du erhältst einen Trank!" |
| `{1|Def}` | The same, capitalised (start of a sentence). |
| `{1|de.def}`, `{1|a.def}`… | Contractions and other articles the language defines. |

Articles, by language (all in `locales.json`, so you can add more):

| Language | Articles |
| --- | --- |
| `de` | `def`, `def.acc`, `def.dat`, `def.gen`, `indef` (+ `.acc`/`.dat`/`.gen`), `kein`, `kein.acc`, `dein`, `dein.acc`, `dein.dat`, `zu.def` (zum/zur), `in.def` (im), `von.def` (vom) |
| `fr` | `def` (le/la/l’/les), `indef`, `de.def` (du/de la/de l’/des), `a.def` (au/à la/à l’/aux), `de` (de/d’), `ce` (ce/cet/cette/ces), `ton`, `son` |
| `it` | `def` (il/lo/la/l’/i/gli/le), `indef` (un/uno/una/un’), `di.def`, `a.def`, `da.def`, `in.def`, `su.def` |
| `es`, `es_419` | `def` (el/la/los/las, el agua), `indef`, `de.def` (del), `a.def` (al), `este`, `tu` |

For articles to be right, each **noun** row (species, item, move, ability, type,
ribbon and trainer type names) has two extra columns:

- `gender`: `m`, `f` or `n` (German). Empty means the language's default
  (masculine); the validator counts nouns without one.
- `sound`: how the noun starts, if the guess is wrong. French and Italian guess
  `vowel` from the first letter (so h is treated as mute; write `consonant` for
  an aspirated h, e.g. "le Hérisson"). Italian guesses `special` (lo/uno/gli)
  for s+consonant, z, gn, ps, pn, x and y. Spanish feminine nouns starting
  with a stressed a ("el agua") need `special` by hand.

Plural item names (`name_plural`) take the gender of the singular row.

Numbers shown with thousands separators use the language's separator
(`1.234` in German, Italian and Spanish, `1 234` in French, `1,234` in Latin
American Spanish).

## Validation

**Errors** (the build stops):

- a CSV that can't be read (not UTF-8, broken quoting, a row with more fields
  than the header);
- a duplicate key, an unknown status, gender or sound value;
- control codes, `{n}` placeholders or `{n:format}` formats that don't match
  the English, unknown codes, unbalanced tags;
- a grammar token that is malformed or uses an article the language doesn't
  have;
- a character the game's font can't draw (e.g. `€`);
- a word wider than its text box (it would run off the edge);
- two rows the engine looks up by the same English, translated differently.

**Warnings** (fail only with `STRICT=1`):

- untranslated rows (summarised per language: English is shown for them);
- `stale` rows; rows whose key is no longer in the game; game text with no
  row yet; English columns out of date (run `make update-locales`);
- text that needs more lines than its box (for messages: more lines than the
  box shows *and* more than the English needs);
- a name wider than the widest English name of the same kind;
- style codes that differ, `{n}` placeholders the translation leaves out,
  leading or trailing spaces that the English doesn't have;
- translated nouns without a gender;
- graphics with English text that have no version for the language.

Messages look like this:

```text
error: de/items.csv:42 (POTION.description): control codes differ from the English: missing \pn
warning: fr/events/map003.csv:7 (ev006.p1.c001): needs 3 lines; the box shows 2 (the English needs 2)
de (Deutsch): 0 errors, 12 warnings, 2371 of 13701 strings translated (17.3%).
```

## Text box sizes

Widths are measured with the game's own fonts (`src/assets/fonts`) exactly as
mkxp-z sizes them (the font size is the cell height), and text is wrapped the
way the engine wraps it.

- **Messages** (events, trainer and phone speeches): the message window is
  214 px wide (256 minus the frame border and padding) with 2 lines per box.
  Longer text still works (the box scrolls with a pause arrow), so it's only a
  warning when a translation needs more lines than the English. `\l[n]`
  changes the number of lines. `\PN` is measured as 7 wide letters, `\v[n]` as
  5 digits and `{n}` as a long Pokémon name (`samples` in `locales.json`).
- **Fixed boxes**, where text that doesn't fit is cut off (`fields` in
  `locales.json`): Summary ability and move descriptions, ribbon descriptions,
  Pokédex entries and Bag item descriptions.
- **Names**: compared with the widest English name of the same kind, since the
  UI was laid out for those.

If you change a UI layout, update `fields` in `locales.json` to match.

## Localized graphics

Some graphics have English text drawn into them (the battle command buttons,
"Lv." and "HP" labels, status icons, Pokédex and Summary backgrounds, the
trainer card, the title screen...). To replace one for a language, put your
version at the same path under the language's `graphics/` folder:

```
src/assets/graphics/UI/Battle/cursor_command.png          English
src/assets/locales/de/graphics/UI/Battle/cursor_command.png   German
```

- Draw it at the same 2× size as the English source; the build halves it like
  every other graphic into `build/Graphics/Locales/<lang>/`.
- It must have the same dimensions as the English graphic (the UI code
  expects them). If a different size is intended, add `"de/UI/..."` (or just
  the path, for every language) to `graphics_size_exceptions` in
  `locales.json`.
- A file with no English counterpart is reported, as it's probably misnamed.
- `graphics_with_text` in `locales.json` lists the graphics known to contain
  English text; each language gets a warning listing those it hasn't replaced
  yet. Add your own graphics to it.

In game, every bitmap loaded by file name (UI, pictures in events, titles,
windowskins...) uses the current language's version if there is one; the
build writes an index (`Data/graphics_<lang>.dat`), so the game never searches
folders.

## Choosing the language in game

Like the official games, **the language belongs to the save file** and can't
be changed afterwards:

- With no save file, the game asks for the language when it starts, before the
  title screen. Each language is shown in its own language, the cursor starts
  on the system's language, and the choice is confirmed in the chosen language.
- Choosing **New Game** when a save file exists asks again, since a new save is
  being started.
- Otherwise the save's language is used. There is no language option in the
  load screen or the Options screen.

Scripts can use `pbCurrentLanguage` (the `Settings::LANGUAGES` entry),
`pbCurrentLanguageCode` (`"de"`) and `pbLoadLanguage(index)`.

Saves from before this system (game version below 1.1.0) are converted when
loaded: they keep their language, and the player's language ID is set from it.

## The language of Pokémon

Every Pokémon already stores its original trainer's language
(`Pokemon::Owner#language`), which the Masuda method and the traded-Pokémon
Exp. bonus use. It now comes from the language the player chose, instead of the
computer's system language:

- `pkmn.language` is the language ID of the game the Pokémon was originally
  obtained in, and `pkmn.language_tag` its tag (`"GER"`).
- Pokémon the player catches, hatches or receives, and NPC trainers' Pokémon,
  get the game's language.
- In-game trades and gifts can give Pokémon from another language:

  ```ruby
  pbStartTrade(pbGet(1), :HAUNTER, "Gengar-Kind", "Lena", 1, 5)   # a German Haunter
  pbAddForeignPokemon(:SHUCKLE, 20, "Pierre", nil, 0, true, 3)     # a French Shuckle
  ```

  Without the language argument they get the game's language.
- The Summary screen shows the tag next to the trainer ID of a Pokémon whose
  language differs from the player's.

## Adding a language

1. Add it to `languages` in `tools/importer/locales/locales.json` (code,
   name, language ID, tag, plural rule, thousands separator, genders) and add
   its articles under `grammar` (or `"same_as": "<code>"`).
2. Add it to `Settings::LANGUAGES` in `src/data/001_Settings.rb`.
3. Run `make update-locales` to create its CSVs.
4. Check the font has every character the language needs (the validator
   reports the ones it doesn't).

## How it works

`tools/importer/locales/` (plain Python 3, plus two small Ruby helpers):

| File | Role |
| --- | --- |
| `locales.py` | Command line: `update`, `validate`, `build BUILD_DIR` |
| `locales.json` | Languages, grammar, box sizes, samples, graphics with text |
| `locjson/sources.py` | Gathers the English text (uses the PBS converter's JSON loader) |
| `extract_events.rb` | Reads event text from the RMXP maps, replaying the compiler's Show Text fixes |
| `locjson/csvio.py` | Reads, writes and updates the CSVs |
| `locjson/codes.py` | Control codes, grammar tokens and text layout |
| `locjson/fonts.py` | Glyph widths from the TrueType fonts, sized like mkxp-z |
| `locjson/validate.py` | The checks |
| `locjson/compile.py`, `write_messages.rb` | Writes the message files (Marshal) |
| `locjson/graphics.py` | Checks and builds localized graphics |

In the game (`src/data`):

- `001_Technical/003_Intl_Messages.rb`: the message files (stock Essentials,
  plus `MessageTypes::LOCALE_DATA`).
- `001_Technical/003_Intl_Grammar.rb`: grammar tokens, used by `_INTL`,
  `_ISPRINTF`, `_MAPINTL` and message display.
- `001_Technical/003_Intl_Graphics.rb`: localized graphics.
- `019_Utilities/001_Utilities.rb`: `pbChooseLanguage`, `pbLoadLanguage`,
  `pbGetLanguage`.

The message files have the layout Essentials always used, so the debug menu's
"Extract text"/"Compile text" options still work, but the CSVs are the
source: compiled files in `build/Data` are overwritten by the next `make`.
