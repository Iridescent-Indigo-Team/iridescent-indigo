"""@package tiledc.stairs
Validation rules for sideways stairs (terrain tags StairsLeft and StairsRight).

A flight of sideways stairs is a 45 degree diagonal band of tiles that the game
walks with left/right only (Game_Character#resolve_step). StairsLeft tiles
climb when walking left, so a flight runs from bottom right to top left;
StairsRight is the mirror image. Flights are entered and left horizontally,
from the landings at either end.

Rules:
  - errors: a stair tile whose passage blocks walking left or right; a Spawn
    or the start position on a stair tile; a Strength boulder on a stair tile
    (boulders can't be pushed onto, along or off stairs);
  - warnings: a stair tile with no neighbour of the same flight (it's walked
    like flat ground); a flight end whose landing can't be walked onto.

The terrain tag of a cell is worked out like Game_Map#terrain_tag: the top
layer's tile with a tag other than None, Neutral or Bridge.
"""

## Terrain tag name -> which way the flight climbs.
STAIR_TAGS = {"StairsLeft": "left", "StairsRight": "right"}
## Tags the game skips when finding a cell's terrain tag.
SKIPPED_TAGS = ("None", "Neutral", "Bridge")
## Tags whose passage the game ignores.
IGNORE_PASSABILITY_TAGS = ("Neutral",)
## RMXP passage bit per direction (Game_Map: 1 << (d / 2 - 1)).
PASSAGE_BITS = {2: 0x01, 4: 0x02, 6: 0x04, 8: 0x08}
## Strength boulder event scripts (the template's script file name).
BOULDER_SCRIPTS = ("strength_boulder.rb",)


class StairMap:
    """Terrain and passability of one compiled map, for the stair rules."""

    def __init__(self, width, height, tile_data, layers, tables, tags):
        """@param tile_data RMXP tile ids, layer-major (x + y*width + z*width*height)
        @param layers number of layers in tile_data
        @param tables (passages, priorities, terrain_tags) of the map's combined tileset
        @param tags tiles.TerrainTags
        """
        ## Map width in tiles.
        self.width = width
        ## Map height in tiles.
        self.height = height
        self._data = tile_data
        self._layers = layers
        self._passages, self._priorities, terrain = tables
        self._tag_names = [tags.name(n) for n in terrain]
        ## (x, y) -> "left" or "right", for every stair tile.
        self.stairs = {}
        for y in range(height):
            for x in range(width):
                kind = STAIR_TAGS.get(self.terrain(x, y))
                if kind:
                    self.stairs[(x, y)] = kind

    def valid(self, x, y):
        """@return whether (x, y) is on the map"""
        return 0 <= x < self.width and 0 <= y < self.height

    def _stack(self, x, y):
        """Tile ids at (x, y), top layer first, skipping empty ones."""
        i = x + y * self.width
        size = self.width * self.height
        for z in reversed(range(self._layers)):
            tid = self._data[i + z * size]
            if tid and tid < len(self._tag_names):
                yield tid

    def terrain(self, x, y):
        """@return the terrain tag name the game sees at (x, y)"""
        for tid in self._stack(x, y):
            name = self._tag_names[tid]
            if name not in SKIPPED_TAGS:
                return name
        return "None"

    def passable(self, x, y, d):
        """Whether the player (walking) can leave or enter (x, y) on side d,
        like Game_Map#playerPassable? off a bridge.

        @param d 2, 4, 6 or 8
        @return bool
        """
        bit = PASSAGE_BITS[d]
        for tid in self._stack(x, y):
            name = self._tag_names[tid]
            if name == "Bridge" or name in IGNORE_PASSABILITY_TAGS:
                continue
            passage = self._passages[tid]
            if passage & bit or passage & 0x0f == 0x0f:
                return False
            if self._priorities[tid] == 0:
                return True
        return True

    def stair_kind(self, x, y):
        """@return "left", "right" or None"""
        return self.stairs.get((x, y))


def _slope(kind):
    """The diagonal neighbours of a stair tile along its flight.

    @return ((dx, dy) one tile up the flight, (dx, dy) one tile down it)
    """
    return ((-1, -1), (1, 1)) if kind == "left" else ((1, -1), (-1, 1))


def check_map(stair_map, spawns, events, problems, rel):
    """Checks the stair rules on one map.

    @param stair_map StairMap
    @param spawns dict name -> [x, y, direction]
    @param events event IRs (dicts with id, name, x, y, script)
    @param problems problems.Problems
    @param rel the map's path for messages
    """
    sm = stair_map
    for (x, y), kind in sorted(sm.stairs.items(), key=lambda item: (item[0][1], item[0][0])):
        where = "tile %d,%d" % (x, y)
        tag = "StairsLeft" if kind == "left" else "StairsRight"
        if not sm.passable(x, y, 4) or not sm.passable(x, y, 6):
            problems.error(rel, where, "%s tile blocks walking left or right, so its flight can't be "
                                       "walked (clear block_left and block_right)" % tag)
        up, down = _slope(kind)
        has_up = sm.stair_kind(x + up[0], y + up[1]) == kind
        has_down = sm.stair_kind(x + down[0], y + down[1]) == kind
        if not has_up and not has_down:
            problems.warning(rel, where, "%s tile has no %s tile diagonally %s it, so it's walked like flat "
                                         "ground (a flight needs at least two tiles)"
                             % (tag, tag, "up-left or down-right of" if kind == "left" else
                                "up-right or down-left of"))
            continue
        # Flight ends: the landing is beside the end tile, away from the flight.
        for has_next, step in ((has_up, up), (has_down, down)):
            if has_next:
                continue
            lx = x + step[0]
            if not sm.valid(lx, y):
                continue   # may continue on a connected map
            side = 4 if step[0] < 0 else 6
            if not sm.passable(lx, y, 10 - side):
                problems.warning(rel, where, "the %s end of this flight has no landing: tile %d,%d can't be "
                                             "walked onto from the stairs"
                                 % ("top" if step[1] < 0 else "bottom", lx, y))
    for name, (x, y, _direction) in sorted(spawns.items()):
        if (x, y) in sm.stairs:
            problems.error(rel, "spawn %r" % name, "is on a sideways stairs tile (%d,%d); put spawns on "
                                                   "flat ground" % (x, y))
    for e in events:
        script = e.get("script") or ""
        if (e["x"], e["y"]) in sm.stairs and script.replace("\\", "/").rsplit("/", 1)[-1] in BOULDER_SCRIPTS:
            problems.error(rel, "event %d %r" % (e["id"], e.get("name", "")),
                           "is a Strength boulder on a sideways stairs tile; boulders can't be pushed "
                           "on stairs")


def check_start(system, results, problems, system_rel):
    """The game's start position can't be on a stair tile.

    @param system the System data (system.json) or None
    @param results compiled maps (compiler.MapResult with a stair_map)
    @param system_rel system.json's path for messages
    """
    if not system:
        return
    start = (system.get("start_x"), system.get("start_y"))
    for r in results:
        if r.entry["id"] == system.get("start_map_id") and r.stair_map and start in r.stair_map.stairs:
            problems.error(system_rel, "start position", "is on a sideways stairs tile (%d,%d) of map %d; "
                                                         "start on flat ground" % (start[0], start[1],
                                                                                   r.entry["id"]))
