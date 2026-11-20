"""@package tiledc.connections
Map connections from a Tiled world file, and world layouts from Essentials
connections (for importing).

Maps placed in src/tiled/maps/pokessentials.world whose edges touch are
connected, like Essentials' map_connections.txt: a connection
[map, side, offset, other_map, other_side, other_offset] says that point
`offset` along `side` of `map` meets point `other_offset` along `other_side` of
`other_map`. The world file is only read at build time.

Connections that can't be laid out in one consistent world (rare loops) are
kept as explicit "connections" map properties:
`N 0 Route 1 S 4` per line (side, offset, other map name or id, other side,
other offset).
"""

import os

from .config import TILE
from .problems import TiledError
from .tiledio import load_json, save_json

## Opposite sides.
OPPOSITE = {"N": "S", "S": "N", "E": "W", "W": "E"}


class Placed:
    """A map's rectangle in the world, in tiles."""

    def __init__(self, map_id, x, y, width, height):
        self.map_id, self.x, self.y, self.width, self.height = map_id, x, y, width, height

    def __repr__(self):
        return "Placed(%r, %d, %d, %d, %d)" % (self.map_id, self.x, self.y, self.width, self.height)


def connection(a, b):
    """The connection between two placed maps if they share an edge.

    @return [a_id, side, offset, b_id, other_side, other_offset] or None
    """
    def overlap(a0, alen, b0, blen):
        return min(a0 + alen, b0 + blen) - max(a0, b0) > 0

    if b.y + b.height == a.y and overlap(a.x, a.width, b.x, b.width):
        side, (a0, b0) = "N", (a.x, b.x)
    elif a.y + a.height == b.y and overlap(a.x, a.width, b.x, b.width):
        side, (a0, b0) = "S", (a.x, b.x)
    elif b.x + b.width == a.x and overlap(a.y, a.height, b.y, b.height):
        side, (a0, b0) = "W", (a.y, b.y)
    elif a.x + a.width == b.x and overlap(a.y, a.height, b.y, b.height):
        side, (a0, b0) = "E", (a.y, b.y)
    else:
        return None
    return [a.map_id, side, max(0, b0 - a0), b.map_id, OPPOSITE[side], max(0, a0 - b0)]


def overlapping(a, b):
    """@return True if two placed maps cover a common tile."""
    return (a.x < b.x + b.width and b.x < a.x + a.width and
            a.y < b.y + b.height and b.y < a.y + a.height)


def world_connections(placed):
    """Every connection between touching maps, sorted.

    @param placed list of Placed
    """
    result = []
    items = sorted(placed, key=lambda p: p.map_id)
    for i, a in enumerate(items):
        for b in items[i + 1:]:
            c = connection(a, b)
            if c:
                result.append(c)
    return result


def load_world(path, registry):
    """Reads a world file.

    @param registry Registry, to turn file names into map ids
    @return (list of Placed, list of (file name, message) for unknown or
        misplaced maps)
    """
    if not os.path.isfile(path):
        return [], []
    world = load_json(path)
    base = os.path.dirname(os.path.abspath(path))
    placed, problems = [], []
    for m in world.get("maps", []):
        file = os.path.normpath(os.path.join(base, m.get("fileName", "")))
        entry = registry.by_file(file)
        if entry is None:
            problems.append((m.get("fileName"), "isn't in the map registry"))
            continue
        x, y = m.get("x", 0), m.get("y", 0)
        if x % TILE or y % TILE:
            problems.append((m.get("fileName"), "isn't placed on the 32px tile grid"))
        placed.append(Placed(entry["id"], x // TILE, y // TILE,
                             m.get("width", 0) // TILE, m.get("height", 0) // TILE))
    return placed, problems


def save_world(path, registry, placed):
    """Writes a world file from Placed rectangles (sizes in tiles)."""
    base = os.path.dirname(os.path.abspath(path))
    maps = []
    for p in sorted(placed, key=lambda p: p.map_id):
        entry = registry.by_id(p.map_id)
        rel = os.path.relpath(registry.map_path(entry), base).replace(os.sep, "/")
        maps.append({"fileName": rel, "height": p.height * TILE, "width": p.width * TILE,
                     "x": p.x * TILE, "y": p.y * TILE})
    return save_json(path, {"maps": maps, "onlyShowAdjacentMaps": False, "type": "world"})


def parse_explicit(text, name_to_id):
    """Parses an explicit "connections" map property.

    @return (list of [side, offset, other_id, other_side, other_offset], errors)
    """
    result, errors = [], []
    for raw in (text or "").replace(";", "\n").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) < 5:
            errors.append("%r: expected 'side offset other_map other_side other_offset'" % line)
            continue
        side, offset, other_side, other_offset = parts[0].upper()[:1], parts[1], parts[-2].upper()[:1], parts[-1]
        other = " ".join(parts[2:-2])
        other_id = int(other) if other.isdigit() else name_to_id.get(other)
        if other_id is None:
            errors.append("%r: no map named %r" % (line, other))
            continue
        if side not in OPPOSITE or OPPOSITE[side] != other_side:
            errors.append("%r: %s must connect to %s" % (line, side, OPPOSITE.get(side, "N/E/S/W")))
            continue
        try:
            result.append([side, int(offset), other_id, other_side, int(other_offset)])
        except ValueError:
            errors.append("%r: offsets must be numbers" % line)
    return result, errors


def layout(sizes, connections, gap=8):
    """Places maps in one world from Essentials connections.

    Connected groups are laid out by following their connections; groups and
    unconnected maps are then put in rows, `gap` tiles apart, so that they
    never touch. A connection that would contradict an earlier placement (or
    make maps overlap) is returned as leftover, to be stored explicitly.

    @param sizes dict map id -> (width, height)
    @param connections list of [map, side, offset, other, other_side, other_offset]
    @return (dict map id -> Placed, list of leftover connections)
    """
    adjacency = {}
    for c in connections:
        if c[0] in sizes and c[3] in sizes:
            adjacency.setdefault(c[0], []).append(c)
            adjacency.setdefault(c[3], []).append(c)
    pairs = {}
    for c in connections:
        pairs.setdefault((min(c[0], c[3]), max(c[0], c[3])), set()).add(tuple(normalise(c)))
    placed_groups = []
    seen = set()
    leftover = []
    used = set()

    def position_of(c, known, other):
        """Position of `other` from the placed map of connection c."""
        a, side, off, b, _, boff = c
        if known == a:
            pa = group[a]
            w, h = sizes[b]
            if side == "N":
                return pa.x + off - boff, pa.y - h
            if side == "S":
                return pa.x + off - boff, pa.y + pa.height
            if side == "W":
                return pa.x - w, pa.y + off - boff
            return pa.x + pa.width, pa.y + off - boff
        pb = group[b]
        w, h = sizes[a]
        if side == "N":     # a is south of b
            return pb.x + boff - off, pb.y + pb.height
        if side == "S":
            return pb.x + boff - off, pb.y - h
        if side == "W":
            return pb.x + pb.width, pb.y + boff - off
        return pb.x - w, pb.y + boff - off

    for start in sorted(sizes):
        if start in seen:
            continue
        group = {start: Placed(start, 0, 0, *sizes[start])}
        seen.add(start)
        queue = [start]
        while queue:
            current = queue.pop(0)
            for c in adjacency.get(current, []):
                key = id(c)
                if key in used:
                    continue
                other = c[3] if c[0] == current else c[0]
                x, y = position_of(c, current, other)
                if other in group:
                    used.add(key)
                    p = group[other]
                    if (p.x, p.y) != (x, y):
                        leftover.append(c)
                    continue
                candidate = Placed(other, x, y, *sizes[other])
                clash = any(overlapping(candidate, p) for p in group.values())
                for p in group.values():
                    touching = connection(candidate, p)
                    if touching and tuple(normalise(touching)) not in \
                            pairs.get((min(other, p.map_id), max(other, p.map_id)), ()):
                        clash = True   # would touch a map it isn't connected to (that way)
                if clash or other in seen:
                    used.add(key)
                    leftover.append(c)
                    continue
                used.add(key)
                group[other] = candidate
                seen.add(other)
                queue.append(other)
        placed_groups.append(group)

    # Normalise each group to start at (0, 0) and put the groups in rows.
    result = {}
    cursor_x, cursor_y, row_height, row_limit = 0, 0, 0, 400
    for group in placed_groups:
        min_x = min(p.x for p in group.values())
        min_y = min(p.y for p in group.values())
        width = max(p.x + p.width for p in group.values()) - min_x
        height = max(p.y + p.height for p in group.values()) - min_y
        if cursor_x and cursor_x + width > row_limit:
            cursor_x, cursor_y, row_height = 0, cursor_y + row_height + gap, 0
        for p in group.values():
            result[p.map_id] = Placed(p.map_id, p.x - min_x + cursor_x, p.y - min_y + cursor_y, p.width, p.height)
        cursor_x += width + gap
        row_height = max(row_height, height)
    # Connections the layout produces but the source didn't have would be new
    # connections; that can't happen (clashes are checked above), but check.
    derived = {tuple(normalise(c)) for c in world_connections(result.values())}
    wanted = {(min(c[0], c[3]), max(c[0], c[3])) for c in connections}
    extra = [c for c in derived if (c[0], c[3]) not in wanted]
    if extra:
        raise TiledError("laying out the world created connections that don't exist: %r" % extra[:5])
    # Source connections the world doesn't reproduce (maps that don't share an
    # edge, or loops) are kept explicitly.
    leftover = []
    for c in connections:
        if c[0] in sizes and c[3] in sizes and tuple(normalise(c)) not in derived and c not in leftover:
            leftover.append(c)
    return result, leftover


def merge(world, explicit):
    """World connections plus explicit ones; an explicit connection replaces
    a world one between the same two maps.

    @return sorted list of normalised connections
    """
    result = {}
    for c in world:
        n = normalise(c)
        result[(n[0], n[3])] = n
    for c in explicit:
        n = normalise(c)
        result[(n[0], n[3])] = n
    return sorted(result.values())


def normalise(c):
    """A connection with the lower map id first, for comparisons."""
    if c[0] > c[3]:
        return [c[3], c[4], c[5], c[0], c[1], c[2]]
    return list(c)
