# Making maps in Tiled

Pokessentials maps are made in [Tiled](https://www.mapeditor.org) (1.10 or
newer) instead of RPG Maker XP. The build compiles them into the same
`.rxdata` files and PBS data the engine has always read. Map loading in the
game is unchanged, and builds still work on Android: everything is converted
on your computer, so the game reads no JSON at runtime.

- [Setting up](#setting-up)
- [What lives where](#what-lives-where)
- [Rules](#rules)
- [Maps](#maps)
- [Tilesets and tile data](#tilesets-and-tile-data)
- [Sideways stairs](#sideways-stairs)
- [Autotiles](#autotiles)
- [Tile layers](#tile-layers)
- [Map connections](#map-connections)
- [Events](#events)
- [Event templates](#event-templates)
- [Common events and system data](#common-events-and-system-data)
- [Atmospheres (fogs, panoramas and more)](#atmospheres)
- [Validation and text](#validation-and-text)
- [Replacements for the Essentials editors](#replacements-for-the-essentials-editors)
- [Android](#android)
- [How the build works](#how-the-build-works)
- [Troubleshooting](#troubleshooting)

## Setting up

You need what [BUILDING.md](BUILDING.md) lists (Python 3 with Pillow, Ruby 3),
plus [Tiled](https://www.mapeditor.org) 1.10 or newer.

1. Install the Essentials assets, if you haven't already:

   ```bash
   make install-assets
   ```

2. Import the RPG Maker XP maps into Tiled. This is a one-time step.

   ```bash
   make import-rxdata
   ```

   It writes `src/tiled/` (maps, tilesets, event scripts, common events,
   system data), converts the autotiles and makes the event previews. The map
   metadata, encounters and connections move from `src/pbs` onto the maps;
   the old copies are deleted from `src/pbs` (git still has them). To import
   another project's data, use `make import-rxdata DATA=path/to/Data`.

3. Open the project in Tiled:

   ```bash
   ./tiled.sh
   ```

   Or open `src/tiled/pokessentials.tiled-project` from Tiled
   (Project > Open Project). The project loads the Pokessentials extensions and
   custom types. Tiled asks whether to enable the extensions the first time;
   say yes.

4. Build and play:

   ```bash
   make run
   ```

From now on `make` compiles `src/tiled` on every build. Only the maps that
changed cost anything, and the compile is skipped completely when nothing
changed. Commit `src/tiled` like any other source.

Until `src/tiled/maps/registry.json` exists, nothing changes: the maps still
come from `src/assets/data`.

## What lives where

| Path | What |
|---|---|
| `src/tiled/pokessentials.tiled-project` | Tiled project: extensions and custom types (`make tiled-project` regenerates the types from the engine) |
| `src/tiled/maps/registry.json` | **Map registry**: id, file, name, parent and order of every map (replaces `MapInfos.rxdata`) |
| `src/tiled/maps/*.tmj` | Maps |
| `src/tiled/maps/pokessentials.world` | World: where maps sit next to each other ([map connections](#map-connections)) |
| `src/tiled/tilesets/*.tsj` | Tilesets, with [tile data](#tilesets-and-tile-data) |
| `src/tiled/tilesets/autotiles/*.tsj` | Converted [autotiles](#autotiles) (their `.png` files are generated and not committed) |
| `src/tiled/tilesets/registry.json` | Stable RMXP tileset ids for each combination of tilesets |
| `src/tiled/events/<map>/*.rb` | Event commands, one file per event |
| `src/tiled/common_events/*.rb` | Common events |
| `src/tiled/system.json` | System data: switch and variable names, start position, title, sounds... |
| `src/tiled/atmospheres/*.json` | [Atmosphere groups](#atmospheres) |
| `src/tiled/templates/` | [Event templates](#event-templates) |
| `src/tiled/extensions/` | Tiled extensions |
| `src/tiled/generated/` | Event previews (generated, not committed) |
| `tools/importer/tiled/` | The compiler and importer (`tiled_compiler.py --help`) |

## Rules

RPG Maker XP data has limits, so a few Tiled features can't be used. The
extension reports these when you save, and the build refuses them:

- **Orthogonal maps only**: no isometric, staggered or hexagonal maps.
- **No infinite maps.** Give every map a fixed size.
- **32×32 tiles** on maps and every tileset. Graphics are drawn at twice the
  game's size and halved by the build, like all graphics in `src/assets`.
- **No flipped or rotated tiles.**
- **At most 3 tiles stacked on one tile**, after
  [flattening](#tile-layers).
- **At most 7 autotiles per map.**
- **Tilesets are saved as their own `.tsj` files**, not embedded in maps.

## Maps

### Creating a map

Use **Map > New Pokessentials Map...** in Tiled. It:

- registers the next free map id,
- creates the map with three tile layers, an `Events` object layer and an
  `Atmosphere` group,
- can reuse the current map's tilesets,
- adds the map to the world, away from the other maps.

You can also run `tiled_compiler.py new-map "Name" --width 20 --height 15`.

Don't make maps with Tiled's own *File > New Map*: such a map isn't in the
registry, so it won't get an id or be built.

### The map registry

`src/tiled/maps/registry.json` lists every map:

```json
{"id": 2, "file": "002_lappet_town.tmj", "name": "Lappet Town", "parent": 0, "order": 2, "expanded": false}
```

- **`id`** is the map's id in the game. Keep it stable: saves, transfers and
  PBS data refer to it.
- **`name`** is the name shown in the debug warp list. Transfers can also use
  it (see [Transfers and spawns](#transfers-and-spawns)).
- **`parent`** and **`order`** build the map tree (`pbMapTree`).

You can edit this file by hand, for example to rename a map or move it in the
tree.

### Map properties

Maps have the class `Map`, so the Properties panel shows these fields:

| Property | What |
|---|---|
| `metadata` | The map's `map_metadata.txt` entry. Every field the engine supports is listed: name, outdoor, show area, bicycle, weather, town map position, battle backgrounds and music, flags... Only the fields you change are written. Fields that are themselves groups (town map position, healing spot, weather, town map size) need all their numbers set. The flags `NoFollowingPokemon` and `ShowFollowingPokemon` control the [following Pokémon](FOLLOWING_POKEMON.md) |
| `encounters` | Wild encounters, one entry per encounter type. `slots` lists the Pokémon as `60 TENTACOOL 14-19; 30 MANTYKE 15-16`: the chance, the species, then a level or a range of levels. `step_chance` is the chance per step; -1 uses the type's default. Add `encounters_v1`, `encounters_v2`... properties (type `Encounters`) for encounter versions |
| `bgm`, `autoplay_bgm`, `bgs`, `autoplay_bgs` | The map's music and background sound |
| `atmosphere` | The [atmosphere group](#atmospheres) the map uses |
| `connections` | Extra [map connections](#map-connections) |

## Tilesets and tile data

A tileset is an ordinary Tiled tileset with 32px tiles. A map can use several
tilesets.

### Tile numbering across tilesets

RPG Maker XP gives a map one tileset and 7 autotiles, so the compiler
combines them:

- **Autotiles** fill the 7 autotile slots, in the order the map lists them.
  Tile *k* of autotile *n* becomes RMXP tile `48 × (n + 1) + k`.
- **Regular tilesets** are stacked into one combined tileset, in the order the
  map lists them. A tileset's tile *t* becomes `384 + 8 × first row + t`.
  Tilesets of any width are reflowed into RPG Maker's 8 columns.

Every map that uses the same tilesets shares one combined tileset. Its image
is generated at `build/Graphics/Tilesets/Tiled/<id>.png`. When a map uses
exactly one 8-column tileset, the tileset's own image is used and nothing is
generated.

Combined tileset ids are kept in `src/tiled/tilesets/registry.json`. New
combinations are added when the compiler first sees them. Commit that file so
the ids don't change: `dungeon_tilesets.txt` and some plugins refer to
tileset ids.

### Tile data: passage, priority, terrain, surf

Each tile's data is its `TileData` property, edited in Tiled's tileset
editor. Select several tiles to change them all at once.

| Field | What |
|---|---|
| `block_down`, `block_left`, `block_right`, `block_up` | The directions the tile can't be passed in. All four means a wall |
| `priority` | 0 is drawn under the player; 1-5 are drawn over them (roofs, treetops) |
| `terrain_tag` | Water (surfable), DeepWater, StillWater, Waterfall, Grass, TallGrass, Ledge, Ice, Bridge, Sand, [StairsLeft, StairsRight](#sideways-stairs)... The list comes from `GameData::TerrainTag`, so tags you add to the engine appear after `make tiled-project` |
| `bush` | The bottom of characters standing on it is hidden |
| `counter` | Characters can be talked to across it |
| `extra_passage` | Any other RPG Maker passage bits (rarely used; kept from imports) |

Autotiles keep their data on the tileset itself (the tileset's `TileData`
property). It applies to all 48 of their tiles.

**Map > Show Collision Overlay** draws a temporary layer over the map that
marks:

- sideways stairs (pink)
- blocked tiles (red)
- one-way tiles (orange)
- water you can surf (blue)
- ledges (yellow)
- grass (green)
- counters (purple)
- bushes (teal)

Choose it again to remove the overlay. It's never saved.

### Importing and exporting tile data

Tile data can be copied in and out of Tiled. Use **Tileset > Export Tile
Data...** and **Import Tile Data...** in Tiled, or these commands:

```bash
make export-tiledata TILESET=src/tiled/tilesets/outside.tsj OUT=outside.csv
```

```bash
make import-tiledata TILESET=src/tiled/tilesets/outside.tsj FILE=outside.csv
```

```bash
make import-tiledata TILESET=src/tiled/tilesets/outside.tsj FILE=path/to/Tilesets.rxdata ID=1
```

The dumps are `.json` or `.csv` (one row per tile, easy to edit in a
spreadsheet). Tiles are matched by their position in the tileset. Every build
also writes the complete RPG Maker `Tilesets.rxdata` to `build/Data`.

## Sideways stairs

Sideways stairs are flights of steps that run diagonally across the map at
45°, walked with Left and Right only. Paint the stair tiles of a flight with
one of two terrain tags:

| Tag | The flight climbs when walking | Tiles of a 3-step flight |
|---|---|---|
| `StairsLeft` | left | (5,4), (4,3), (3,2): bottom right to top left |
| `StairsRight` | right | (3,4), (4,3), (5,2): bottom left to top right |

Each end of a flight needs a **landing**: a flat tile you can walk onto, beside
the end tile and away from the flight. For the `StairsLeft` example above, the
landings are (6,4) and (2,2).

How characters move:

- Walking onto the end tile of a flight from its landing is a normal
  horizontal step.
- Left or Right on the flight moves one tile across and one tile up or down,
  as long as the flight continues. At the end tile, the step goes
  horizontally onto the landing.
- Up and Down do nothing on stairs: no step, no turn and no bump sound.
  Flights can't be entered from above or below either.
- Characters face left or right while on stairs. A character placed on a stair
  tile (a transfer to a tile, the debug warp) is turned to face down the
  flight.
- Walking, running and cycling all work on stairs. Ice sliding, waterfalls and
  other forced movement end on reaching a flight.
- Strength boulders can't be pushed onto, along or off stairs.
- Followers walk the leader's actual trail, so they follow diagonally along a
  flight.
- Talking to and touching events uses the tile diagonally ahead when the
  player is on a flight.

Events follow stairs too, so NPCs that wander or walk move routes go up and
down flights like the player. To make an event move straight over stair tiles
instead, use the `stairs_off` move route command. `stairs_on` turns stairs
back on. Characters bigger than one tile always ignore stairs.

```ruby
move_route 0, route(stairs_off, move_left, move_left, stairs_on)
```

Both commands are stored as RPG Maker Script move commands (`stairs_off` /
`stairs_on`), so the compiled maps are ordinary RPG Maker XP data.

The validator checks every flight:

| Problem | |
|---|---|
| A stair tile blocks walking left or right (`block_left`/`block_right`) | error |
| A Spawn on a stair tile | error |
| The start position (`system.json`) on a stair tile | error |
| A Strength boulder event on a stair tile | error |
| A stair tile with no tile of its flight diagonally next to it (it's walked like flat ground) | warning |
| A flight end whose landing can't be walked onto (a flight ending at the map's edge isn't checked, since a connected map may continue it) | warning |

Stair tiles show in pink in the [collision overlay](#tilesets-and-tile-data).

## Autotiles

An RPG Maker autotile is a 96×128 sheet that the engine cuts into 48 variants.
`make tiled-assets`, which `make import-rxdata` also runs, converts each one
from `src/assets/graphics/Autotiles` into a Tiled tileset in
`src/tiled/tilesets/autotiles/`. That tileset has:

- the **48 variants**, in RPG Maker's order, so tile *k* is variant *k*;
- a **terrain set**, so you can paint with Tiled's terrain brush and get the
  same edges RPG Maker's autotile pen draws;
- **animation**: autotiles with frames side by side (water, flowers) are
  animated in Tiled. The frame time comes from the `[n]` suffix of the file
  name, as in the game. Only the first 48 tiles can be painted; the rest are
  the animation frames.

To convert other autotiles, use `make tiled-assets ALL=1` (every file in
`Graphics/Autotiles`) or `tiled_compiler.py autotiles "Name"`. Add the result
to a map like any tileset. The game still loads the original autotile
graphic.

## Tile layers

Maps can have as many tile layers as you like, inside groups or not. RPG
Maker XP keeps 3 per tile, so the build flattens them:

- **With 3 tile layers or fewer**, each layer stays on its own RPG Maker
  layer.
- **With more**, the tiles on each spot are packed from the bottom layer up.
  More than 3 tiles on one spot is an error.

Hidden layers are compiled too. Layer offsets and parallax don't apply to tile
layers; use [atmospheres](#atmospheres) for parallax.

## Map connections

Open `src/tiled/maps/pokessentials.world` in Tiled (World > Load World) and
drag maps next to each other. Maps whose edges touch are connected: the
player walks from one to the other, and both are drawn. The build turns
these into `map_connections.txt`. The world file is only read when building,
so it costs nothing in the game.

For connections between maps that don't share an edge, add a `connections`
property to the map, one per line or separated by `;`:

```
N 0 Route 1 S 4
```

That's:

- this map's side (`N`, `E`, `S` or `W`),
- the offset along it,
- the other map's name or id,
- the other map's side,
- the offset along that side.

The importer writes these for Essentials connections that can't be laid out
side by side. An explicit connection replaces a world connection between the
same two maps.

## Events

An event is an object of class **Event** on an object layer (usually
`Events`). The object's name is the event's name.

| Part | Where |
|---|---|
| Position | The tile the object is on |
| `event_id` | The RPG Maker event id. Self switches use it, so keep it stable. It is assigned automatically; copies get a new one when you save |
| `page_0`, `page_1`, ... | Each page's settings: conditions (`switch1`, `switch2`, `variable` and `variable_value`, `self_switch`), graphic (`graphic`, or `tile` as `tileset:number`), `hue`, `direction`, `pattern`, `opacity`, `blend`, movement (`move_type`, `move_speed`, `move_frequency`), options (`walk_anime`, `step_anime`, `direction_fix`, `through`, `always_on_top`) and `trigger` |
| `script` | The `.rb` file with the page commands |
| Other properties | Parameters the script reads with `param(:name)` |

### Event actions in Tiled

The Map menu has these actions. The first three are also on the object's
right-click menu.

| Action | What |
|---|---|
| **New Event...** | Makes an event on the tile you selected with the Rectangular Select tool, with its own script file |
| **Add Event Page** | Adds a page to the selected event |
| **Edit Event Script** | Opens the event's `.rb` in your editor (`$VISUAL` or `$EDITOR`, or the system's default program for `.rb` files) |
| **Insert Event Command...** | Appends a command to a page: text, choices, conditions, switches, transfers, battles, items, move routes, atmosphere changes... |
| **Show Event Graphics** | Shows each event as its first page's graphic, standing on its tile. It needs the previews from `make tiled-assets` |
| **Export Selected Events...** / **Import Event...** | Standalone `.rb` files, to share events between maps and projects. Also `make export-events MAP="Lappet Town" OUT=dir` and `make import-events MAP=3 FILES=...` |

### Event scripts

A script has a `page n, [ ... ]` block per page, in a readable Ruby format.
The importer writes every RPG Maker event in this format:

```ruby
page 0, [
  text("\\bHello, \\PN!"),
  *show_choices(
    choices: ["Yes", "No"],
    cancellation: 2,
    choice1: [
      script("pbReceiveItem(:POTION)"),
      control_self_switch("A", :ON),
    ],
    choice2: [
      text("Maybe later, then."),
    ],
  ),
]

move_route 0, route(move_down, move_up)   # page 0's custom movement
```

The commands are the RPG Maker event commands, with readable names, for
example:

- **Messages**: `text`, `show_choices`, `input_number`, `comment`, `script`
- **Flow**: `condition`, `repeat`, `break_loop`, `label`, `jump_label`,
  `exit_event_processing`, `erase_event`, `call_common_event`
- **Variables**: `control_switches`, `control_variables`,
  `control_self_switch`
- **Map and characters**: `transfer_player`, `transfer`, `event_location`,
  `move_route` (with `move_down`, `turn_up`, `route_wait`, `through_on`,
  `stairs_off`, `stairs_on`...),
  `wait_completion`, `change_transparent_flag`. Characters are `player`,
  `this`, `character(id)`, and `pokemon_follower` for the
  [following Pokémon](FOLLOWING_POKEMON.md)
- **Screen**: `wait`, `change_tone`, `screen_flash`, `screen_shake`,
  `show_picture`, `move_picture`, `erase_picture`, `weather_effect`,
  `atmosphere`
- **Audio**: `play_bgm`, `play_se`, `play_me`, `fade_out_bgm`,
  `memorize_bgm_bgs`, `restore_bgm_bgs`

The full list is in `lib/eevee/rmxp/rpg_factory.rb`.

Two things to know:

- A few commands can't be written in the readable form. They are kept exactly
  as `raw(code, indent, parameters...)`.
- Show/Move Picture coordinates are at the 512×384 source scale. The build
  halves them, like `halve_data.rb` does.

**Parameters**: `param(:item)` is the value of the event's `item` property.
`param(:item, "POTION")` gives a default when the property isn't set. One
script can serve many events this way; that's how the templates work.

### Transfers and spawns

Put an object of class **Spawn** on a map where the player should arrive. Its
name is the spawn's name, and its `direction` property is the way the player
faces (or `retain`). Then transfer by name:

```ruby
transfer(to: "Route 1", spawn: "from_lappet")
transfer(to: "Route 1", x: 4, y: 10, direction: :up, fading: false)
```

`to:` is a map name from the registry (or a map id). The build resolves it to
coordinates, so moving a spawn moves every transfer to it. A transfer to a map
or spawn that doesn't exist is a build error.

## Event templates

`src/tiled/templates/` holds object templates for common events. Place them
with Tiled's **Insert Template** tool from the Templates panel, then set their
properties:

| Template | Properties |
|---|---|
| `item_ball` | `item` (e.g. `POTION`), `quantity` |
| `hidden_item` | `item`, `quantity` (found with the Itemfinder) |
| `door` | `to` (map name), `spawn` |
| `warp_tile` | `to`, `spawn` (stairs, cave entrances) |
| `sign` | `text` |
| `npc` | `text`; graphic and movement in `page_0` |
| `trainer` | `trainer_type`, `trainer_name`, `intro`, `defeated`, `after`. The name `Trainer(3)` is its sight range |
| `pc`, `berry_plant`, `strength_boulder`, `cut_tree`, `smash_rock`, `headbutt_tree` | none |

Every instance shares the template's script (`templates/events/*.rb`), so
fixing a template fixes all its events. To make one event different, give it
its own `script`. Your own templates work the same way: an Event object saved
as a template, plus a script that uses `param`.

## Common events and system data

Common events are `src/tiled/common_events/<id>_<name>.rb`:

```ruby
common(
  id: 3,
  name: "Fishing",
  trigger: :none,       # :none, :autorun or :parallel
  switch: 1,            # the switch that runs autorun/parallel events
  commands: [
    text("..."),
  ],
)
```

`src/tiled/system.json` is RPG Maker's System data:

- `switches` and `variables` (their names)
- `start_map_id`, `start_x` and `start_y`
- the title screen, windowskin and sounds

## Atmospheres

Atmospheres replace RPG Maker's single fog and panorama per tileset. An
atmosphere is a group of layers drawn behind or over the map. Groups are
defined in `src/tiled/atmospheres/<id>.json` and chosen with a map's
`atmosphere` property:

```json
{
 "name": "Forest mist",
 "fade_frames": 30,
 "layers": [
  {"name": "sky", "graphic": "Panoramas/Clouds", "z": "below", "parallax_x": 0.25, "parallax_y": 0.1},
  {"name": "mist", "graphic": "Fogs/Mist", "z": "above", "opacity": 64, "scroll_x": 20, "blend": "add"},
  {"name": "leaves", "graphic": "Fogs/Leaves", "frames": 4, "frame_duration": 4, "repeat_y": false}
 ]
}
```

| Setting | What (default) |
|---|---|
| `graphic` | Any graphic under `Graphics/`, without extension; not just Fogs and Panoramas |
| `z` | `"below"` the map (like a panorama), `"above"` it (like a fog), or a number (`"above"`) |
| `parallax_x`, `parallax_y` | How far it moves with the camera, separately for x and y: 0 stays on screen, 1 moves with the map, 0.5 is RPG Maker's panorama (1) |
| `scroll_x`, `scroll_y` | Automatic scrolling, in pixels per second (0) |
| `offset_x`, `offset_y` | Starting position in pixels (0) |
| `opacity`, `blend`, `hue`, `tone` | 0-255 (255); `"normal"`, `"add"` or `"subtract"`; hue shift; `[red, green, blue, gray]` |
| `zoom_x`, `zoom_y` | Percent (100) |
| `frames`, `frame_duration` | Animation: frames side by side in the graphic, and the time per frame in 1/20ths of a second (1, 5) |
| `repeat_x`, `repeat_y` | Tile the graphic in each direction (true) |

Pixel values are at the source graphics' scale (2×) and halved by the build.

**Map layers.** A map can also add its own layers as image layers inside its
`Atmosphere` group, with the class `AtmosphereLayer`:

- Tiled previews them with their parallax and repeat settings.
- The image must be in `src/assets/graphics`.
- Opacity, parallax, repeat and offset come from the image layer.
- The other settings are the layer's properties.

**How atmospheres behave:**

- **Drawn once.** One renderer draws all layers, however many connected maps
  are on screen. RPG Maker drew a fog and a panorama per map.
- **Continuous across maps.** Maps with the same group share their layers:
  scrolling and animation carry on when you walk or warp between them. Layers
  scroll by the camera's position in the world, so they line up across
  connected maps.
- **Cross-fade.** Moving to a map with a different group fades the old layers
  out and the new ones in, over the group's `fade_frames`, or
  `Settings::ATMOSPHERE_FADE_FRAMES` if it doesn't set any.
- **Managed outside the map.** `Atmosphere::Manager` owns every effect and is
  saved with the game. Maps only tell it where the player is.

**Changing atmospheres from events:**

```ruby
atmosphere(:mist, opacity: 0, frames: 40)          # fade the mist out over 2 seconds
atmosphere(:mist, scroll_x: 60)                    # windier
script("pbAtmosphere.add(:storm, graphic: 'Fogs/Storm', opacity: 120)")
script("pbAtmosphere.remove(:storm)")
atmosphere(:sky, tone: [-60, -60, 0, 0], frames: 60, persist: true)
script("pbAtmosphere.reset")                       # undo this group's changes
```

`pbAtmosphere.set/add/remove/reset/layer` work from any script. RPG Maker's
own event commands (Change Map Settings: Panorama/Fog, Change Fog Color Tone,
Change Fog Opacity) change the layers named `panorama` and `fog`.

**The rule for changes made by events:** a change lasts until the player
leaves the current atmosphere group, or until it's undone. When the player
comes back, the group's defaults are restored. Add `persist: true` to keep a
change: it's saved with the game and applied every time the player enters
that group, until `pbAtmosphere.reset(persistent: true)`.

The importer turns each tileset's fog and panorama into a group named
`tileset_<name>`. Maps from games still built from RPG Maker (no
atmospheres file) keep their tileset's fog and panorama, through the same
manager.

**Performance:**

- Graphics are loaded, hue-shifted and split into frames once, and shared by
  every layer that uses them.
- A layer that repeats in one direction only is pre-tiled once into a strip.
- Sprite settings are only updated when a layer changes, and hidden layers
  cost nothing.

See [Android](#android) for the low-end settings.

## Validation and text

- **When you save in Tiled**: the extension checks the rules above and shows
  problems in the Issues panel.
- **Map > Validate Project**, or `make validate-tiled`: checks everything
  without building, including every event script (syntax errors with their
  line, unknown commands, missing template parameters, transfers to maps or
  spawns that don't exist). It also checks:
  - tilesets, autotiles, graphics, and duplicate event ids;
  - metadata, encounter slots, connections and atmospheres;
  - [sideways stairs](#sideways-stairs): flights, landings, and spawns,
    boulders or the start position on stairs;
  - tilesets with no tile data at all.
- **Every build** runs the same checks. Errors stop the build and nothing is
  written. Warnings don't, unless you build with `STRICT=1`.
- **`make tiled-text`** writes every message and choice of every map and
  common event to `build/tiled_text.csv`, for proofreading.
- **Translations**: `make update-locales` reads the compiled maps, so
  [LOCALIZATION.md](LOCALIZATION.md) works as before.

## Replacements for the Essentials editors

The in-game debug editors that wrote maps or map data would lose their
changes on the next build, so in games built from Tiled they say where to
make the change instead:

| Essentials tool | In Tiled |
|---|---|
| Edit map_connections.txt (visual connections editor) | Drag maps in the world (`pokessentials.world`) |
| Edit encounters.txt | The map's `encounters` property |
| Edit map_metadata.txt | The map's `metadata` property |
| Edit terrain tags (tileset editor) | `TileData` in Tiled's tileset editor, plus the collision overlay |
| Fix invalid tiles | `make validate-tiled` |
| Map tree / map infos | `maps/registry.json` and Map > New Pokessentials Map |
| RPG Maker's event editor | Event objects and scripts, Insert Event Command, templates |
| RPG Maker's database: common events, system | `common_events/*.rb`, `system.json` |

Warping, resetting trainers, compiling data and the other debug options work
as before. `make pull-pbs` still imports changes made with the in-game PBS
editors, but leaves the map datasets alone: they belong to the maps now.

## Android

Nothing extra is needed:

- Maps compile to the same `.rxdata` files.
- Atmospheres compile to a small Marshal file (`Data/atmospheres.dat`).
- Generated tilesets are ordinary PNGs.
- `make android` includes it all, and the game needs no JSON parser or
  converter at runtime.

To keep games smooth on phones:

- **Keep atmosphere graphics small.** Graphics over
  `Settings::ATMOSPHERE_MAX_TEXTURE_SIZE` (4096px) aren't drawn, because many
  Android GPUs can't load them; the build warns about them.
- **Use repeating layers** rather than huge single images.
- **Low quality:** `Settings::ATMOSPHERE_LOW_QUALITY_ON_ANDROID = true` turns
  off atmosphere animation frames and cross-fades on Android only.
  `ATMOSPHERE_LOW_QUALITY` does the same everywhere.
- **Tall tilesets are fine.** A big combined tileset is folded to fit GPU
  limits by the existing `TilesetWrapper`.

## How the build works

`make` runs `tiled` before `pbs` and `data`. That runs
`tools/importer/tiled/tiled_compiler.py build`, which:

1. Validates each map and turns its tile layers into RMXP tile ids, combining
   tilesets and flattening layers.
2. Collects events, spawns, metadata, encounters and atmospheres, and reads
   the world for connections.
3. Runs `ruby/rxdata_build.rb`. It evaluates the event scripts and writes
   these to `build/Data` (only files whose bytes changed):
   - `Map###.rxdata`, `MapInfos.rxdata`, `Tilesets.rxdata`
   - `CommonEvents.rxdata`, `System.rxdata`
   - `atmospheres.dat`, `tiled_build.dat`
4. Writes the combined tileset images.
5. Copies `src/pbs` to `build/.tiled/pbs` with the map datasets from the maps.
   `make pbs` exports that copy with the usual PBS tools, so map metadata and
   encounters get the same checks as before.

`make data` then copies the rest of `src/assets/data` (animations...), skipping
the files Tiled wrote.

| Target | What |
|---|---|
| `make tiled` | Compile `src/tiled` (also part of `make`). `FORCE=1` rebuilds everything, `STRICT=1` fails on warnings |
| `make validate-tiled` | Check without building |
| `make import-rxdata` | Import RPG Maker data (`DATA=dir`, `FORCE=1` to overwrite `src/tiled`) |
| `make tiled-assets` | Convert autotiles, make event previews, update the project's types |
| `make tiled-project` | Update the project's custom types from the engine |
| `make tiled-text` | Every message, to `build/tiled_text.csv` |
| `make export-events`, `make import-events` | Standalone event files |
| `make export-tiledata`, `make import-tiledata` | Tile data dumps |
| `make test-tiled` | The tools' tests, including a full import and compile round trip of the Essentials sample maps |

After importing a project, you can check that nothing was lost:

```bash
make build
```

```bash
ruby tools/importer/tiled/ruby/roundtrip_check.rb src/assets/data build/Data
```

It compares every map's tiles (by graphic), tile data, events, common events,
the map tree and System, and prints the differences.

## Troubleshooting

- **"Open src/tiled/pokessentials.tiled-project first"**: the extension
  actions need the project open (Project > Open Project, or `./tiled.sh`).
- **Python not found from Tiled**: the actions run `python3` (on Windows,
  `python` or `py`). Install Python 3, or add it to `PATH`, and restart
  Tiled.
- **Autotiles show as empty**: their images are generated. Run
  `make tiled-assets`.
- **"embedded tilesets aren't supported"**: in the map, select the tileset
  and use the Export Tileset button to save it as a `.tsj` next to the
  others.
- **An event's graphic doesn't show in Tiled**: run `make tiled-assets`, then
  Map > Show Event Graphics. The graphic in `page_0` decides what the game
  shows; the preview is only for you.
- **New tileset ids appeared in `tilesets/registry.json`**: a map uses a new
  combination of tilesets. Commit the file.
