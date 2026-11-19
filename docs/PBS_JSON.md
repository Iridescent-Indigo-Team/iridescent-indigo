# Game data as JSON (PBS ⇄ JSON)

Pokémon Essentials keeps its game data (species, moves, items, trainers, …) in
PBS text files that the engine compiles into `Data/*.dat`. In Pokessentials the
source of that data is **JSON in `src/pbs/`**. The build turns the JSON back
into PBS files in `build/PBS/`, and the engine compiles those as usual.

- [Workflow](#workflow)
- [Layout of src/pbs](#layout-of-srcpbs)
- [JSON conventions](#json-conventions)
- [Validation](#validation)
- [The engine schema](#the-engine-schema)
- [names.json and layout.json](#namesjson-and-layoutjson)
- [Files with their own format](#files-with-their-own-format)
- [Adding a new kind of PBS file](#adding-a-new-kind-of-pbs-file)

## Workflow

```bash
make import-pbs
```

Imports `src/assets/pbs/*.txt` (copied there by `install_assets.sh`) into
`src/pbs/`, replacing what is there. The repository's `src/pbs/` was already
imported from the Essentials PBS files, so run this only to start again from a
set of PBS files. Only top-level files are read, so the `Gen N backup` and
`Shadow Pokémon backup` folders are never imported.

```bash
make pbs
```

Validates `src/pbs/` and writes `build/PBS/*.txt`. `make`, `./game.sh` and
`make compile` all do this. The engine then compiles the PBS files into
`build/Data/*.dat`, on the next debug launch or with `make compile`.

```bash
make pull-pbs
```

Imports the PBS files that the in-game debug editors wrote to `build/PBS/` back
into `src/pbs/`. Run it after using the editors and before committing.

`make pbs` never silently overwrites changes made by the debug editors. Every
export records the files it wrote in `build/PBS/.pbs_json_state`. If a file has
changed since then, the export stops:

```text
conflict: moves.txt was changed in build/PBS since the last export (by the in-game editors?).
Not exporting. Run `make pull-pbs` to import those changes into src/pbs first, or export with --force (FORCE=1) to overwrite them.
```

Use `make pbs FORCE=1` to throw those changes away.

Other targets:

| Target | Description |
| --- | --- |
| `make validate-pbs` | Check `src/pbs/` without exporting |
| `make pbs-schema` | Dump the PBS schemas from the engine (see [below](#the-engine-schema)) |
| `make test-pbs` | Run the converter's tests |

The converter can also be run directly:

```bash
python3 -I tools/importer/pbs/pbs_json.py --help
```

`roundtrip DIR` converts a PBS folder to JSON, back to PBS and to JSON again,
and reports anything that changed. Use it to check a PBS folder from another
project before importing it.

## Layout of src/pbs

| Path | Contents |
| --- | --- |
| `src/pbs/<file>.json` | A small PBS file such as `types.txt` or `metadata.txt`, kept in one JSON file |
| `src/pbs/<file>/<entry>.json` | Large PBS files, one JSON file per entry, e.g. `src/pbs/pokemon/bulbasaur.json` |
| `src/pbs/<file>/_index.json` | The order of those entries, and which PBS file each one belongs to |
| `src/pbs/battle_facility/<file>.json` | The trainer and Pokémon files that `battle_facility_lists.txt` names |
| `src/pbs/raw/<file>.txt` | PBS files the compiler doesn't read, kept as text and copied back unchanged |
| `src/pbs/_schema/` | Generated JSON Schemas, for editor completion and checks |

Entry file names are snake_case versions of the entry ids:

- `[PIKACHU,1]` becomes `pokemon_forms/pikachu_1.json`
- `[LEADER_Brock,Brock]` becomes `trainers/leader_brock_brock.json`
- map 5 becomes `encounters/map_005.json`

The id itself is stored inside the file. If two ids would give the same file
name, `_2`, `_3`, … is added.

### What _index.json keeps

The order of entries matters to the compiler. Species numbers and the order
items are listed in both come from the order in the PBS file. `_index.json`
records that order, and splits the entries into the PBS files they came from:

```json
{
  "$schema": "../_schema/index.schema.json",
  "files": [
    {"suffix": "", "bom": true, "entries": ["bulbasaur", "ivysaur", "..."]},
    {"suffix": "gen9", "bom": true, "entries": ["sprigatito", "..."]}
  ]
}
```

A suffix of `gen9` means `pokemon_gen9.txt`. Essentials reads every
`<name>_<suffix>.txt` and remembers each entry's file, so the debug editors
write each entry back to the file it came from. To add an entry, create its
JSON file and add its name to `entries` where it should go. Files in the folder
that the index doesn't list are reported by the validator and not exported.

Datasets kept in one JSON file have the same `files` list, with the entries
written out in full instead of named.

## JSON conventions

- **Keys** are the engine's property names, in lower case: `real_name`,
  `base_stats`, `intro_bgm`. They are the keys of the `GameData` classes'
  `SCHEMA`, not the PBS key names.
- **Section names** become keys of the entry: `id` for `[BULBASAUR]`, and
  `species` and `form` for `[PIKACHU,1]`.
- **Values with several parts** become objects with named keys. The names
  come from `tools/importer/pbs/names.json`:

  ```json
  "base_stats": {"hp": 35, "attack": 55, "defense": 40, "speed": 90, "special_attack": 50, "special_defense": 50},
  "moves": [
    {"level": 1, "move": "PLAYNICE"},
    {"level": 4, "move": "THUNDERWAVE"}
  ],
  "evolutions": [
    {"species": "RAICHU", "method": "Item", "parameter": "THUNDERSTONE"}
  ]
  ```

- **Enumerations** keep their PBS spelling: `"FIRE"`, `"Physical"`,
  `"Medium"`.
- **Missing keys** are left out of the PBS file. The engine then uses its
  default, the same as when a PBS line is missing.
- **Text** is stored without the quote marks the PBS file needs. They are
  added back where the compiler needs them. Text can't contain `#`, because
  the compiler treats everything after it as a comment.
- **Evolution parameters** are integers when the evolution method takes an
  integer (`"parameter": 16` for `Level`), and text otherwise.
- **Pokémon sprite metrics** (`pokemon_metrics`) need no special handling.
  Their values are already in the game's 1× pixels, so unlike the `.rxdata`
  pixel values that `halve_data.rb` halves, they are copied exactly as
  written.
- **Comments** aren't kept. The compiler ignores them, and the engine's PBS
  writer drops them too, so files the debug editors write lose them anyway.

The exported PBS files are written the way the engine's own PBS writer
(`Compiler.write_all`) writes them:

- a UTF-8 BOM (unless the original file had none)
- CRLF line endings
- the "See the documentation on the wiki" header
- `#---` separators between sections
- properties in schema order
- one `Evolution =` line per evolution

The map-name comments the engine adds next to map ids are left out. Importing
a file the debug editors wrote and exporting it again gives the same data.

`make pull-pbs` records what the engine wrote, including the engine's own
changes:

- The compiler sorts encounter slots.
- The Battle Tower Pokémon writer drops item and move ids it doesn't know.
- The Battle Tower trainers writer (`write_battle_tower_trainers`) quotes text
  that already has quote marks again. Text such as `"Man, I lost!"` comes back
  as `"\"Man, I lost!\""`. This is an Essentials bug, so check
  `git diff src/pbs` after pulling those files.

## Validation

`make pbs` validates before it exports, and stops on errors.
`make validate-pbs` runs the same checks on their own:

- **Types**: every value is checked against its schema letter (integer, ≥ 0,
  > 0, number, true/false, id, text), and multi-part values against
  `names.json`. Unknown keys are errors, so a misspelled key is caught.
- **Enumerations** with fixed values (growth rates, natures, evolution
  methods, encounter types, move categories, …) are checked against the
  values the engine dumped.
- **References between files**:
  - a move's type
  - a species' abilities, moves, items and evolution targets
  - form species
  - trainers' Pokémon, items and moves
  - encounter species (forms included, e.g. `VULPIX_1`)
  - regional Dex species
  - metadata trainer types
  - the files named in `battle_facility_lists`
- **Evolution parameters** must match what the method takes: an integer, an
  item id, a move id, and so on.
- **Duplicates** (an id defined twice), and entries missing from or not listed
  in `_index.json`.
- **File rules**: `metadata` needs sections 0 and 1, encounter levels must be
  within the maximum level, map connections must join opposite sides, and a
  regional Dex can't list a species twice.

Errors name the JSON file and the field:

```text
error: src/pbs/moves/tackle.json (type): undefined Type 'FAIRY'
```

Some problems are only **warnings**, because the compiler accepts them. For
example, the Battle Tower files from Essentials name an item `STICK` and a move
`VICEGRIP` that no longer exist, and the compiler skips them.

The JSON Schemas in `src/pbs/_schema/` let editors such as VS Code check values
and complete keys while you type. Every JSON file has a `$schema` reference to
its schema. Cross-file references are only checked by the validator.

## The engine schema

The PBS formats are not written into the converter. They come from
`tools/importer/pbs/engine_schema.json`, which the engine writes from
`GameData::*::SCHEMA`:

```bash
make pbs-schema
```

This runs `./game.sh --dump-schema` headlessly. The game starts with
`POKESSENTIALS_DUMP_SCHEMA` set, loads the plugins, and calls
`Compiler.dump_pbs_schema`, in
`src/data/021_Compiler/005_Compiler_DumpSchema.rb`. The dump contains:

- every GameData class with a PBS file: its base file names, `SCHEMA`,
  `Species.schema(true)` for forms, and `Trainer::SUB_SCHEMA`
- the values of the enumerations those schemas use: hardcoded GameData
  modules, and the hash and array enumerations in the schemas
- evolution parameter types, encounter types and the maximum level

The file is committed, so the converter runs without the engine.

Run `make pbs-schema` again whenever a script or plugin changes a `SCHEMA`.
Plugins are loaded before the dump, so their changes are included.

## names.json and layout.json

`tools/importer/pbs/names.json` is written by hand:

- **`tuples`** names the parts of every multi-part value. Lookups use
  `"<file>.<PBS key>"` first (e.g. `"trainers.SectionName"`), then
  `"<PBS key>"` (e.g. `"BaseStats"`). If a schema has a multi-part value with
  no names, the converter stops with an error saying which entry to add.
- **`aliases`** lists old PBS keys that the compiler renames before compiling
  (`BaseDamage` → `Power`, `VictoryME` → `VictoryBGM`). They are accepted on
  import.
- **`references`** lists text fields whose values must be ids from another
  file, for example the types in `Weaknesses`.

`tools/importer/pbs/layout.json` lists the PBS files that get one JSON file
per entry. Every other file becomes a single JSON file.

## Files with their own format

Most PBS files are read and written straight from their schema. These have
their own formats, mirroring the compiler (`Compiler.compile_*`) and the
engine's writer (`Compiler.write_*`):

| PBS file | JSON |
| --- | --- |
| `encounters.txt` | `{"map", "version", "types": [{"type", "step_chance", "slots": [{"chance", "species", "min_level", "max_level"}]}]}` |
| `trainers.txt` | the trainer's properties plus `"pokemon": [{"species", "level", ...}]`, from `SCHEMA` and `SUB_SCHEMA` |
| `metadata.txt` | section 0 uses `GameData::Metadata`, the others use `GameData::PlayerMetadata` |
| `map_connections.txt` | `{"map", "side", "offset", "other_map", "other_side", "other_offset"}` per line |
| `regional_dexes.txt` | `{"id", "families": [[species, ...], ...]}`, one list per line of the file |
| `battle_facility_lists.txt` | `{"default", "trainers", "pokemon", "challenges"}` per list |
| Battle Tower/Cup trainer files | `{"type", "name", "begin_speech", "end_speech_win", "end_speech_lose", "pokemon_nos"}` |
| Battle Tower/Cup Pokémon files | `{"species", "item", "nature", "evs", "moves"}` per line |

## Adding a new kind of PBS file

A plugin that adds a GameData class with `PBS_BASE_FILENAME` and `SCHEMA` is
picked up automatically:

1. Run `make pbs-schema` to add it to the engine schema.
2. Add names to `names.json` for any multi-part values.
3. Add it to `layout.json` if it should get one file per entry.
4. Run `make import-pbs`, or `make pull-pbs` if its PBS file is in
   `build/PBS/`.

A PBS file with its own format needs a handler class in
`tools/importer/pbs/pbsjson/datasets.py`. Until it has one, the file is kept
as text in `src/pbs/raw/`.
