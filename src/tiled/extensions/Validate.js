/**
 * @file Validate.js
 * Checks maps and tilesets as they're saved, so problems show up in Tiled's
 * Issues panel right away (the compiler checks the same rules again):
 *   - maps must be orthogonal, not infinite, with 16x16 tiles;
 *   - tilesets must have 16x16 tiles and be saved as their own .tsj files;
 *   - tiles can't be flipped or rotated;
 *   - at most 3 tiles can be stacked on one tile (RPG Maker XP's layers);
 *   - at most 7 autotile tilesets per map;
 *   - events get an event id if they have none, and copies of an event get
 *     a new one.
 * Also adds Map > Validate Project, which runs the full validation
 * (including event scripts) with tiled_compiler.py.
 */

(function () {
    "use strict";

    /** Most cells reported per problem, so the Issues panel stays readable. */
    var MAX_REPORTED = 5;

    function checkMap(map) {
        var P = Pokessentials;
        var name = P.stem(map.fileName);
        var problems = 0;
        function error(text) {
            problems++;
            tiled.error(name + ": " + text, function () { tiled.open(map.fileName); });
        }
        if (map.orientation !== TileMap.Orthogonal)
            error("only orthogonal maps are supported (Map > Map Properties > Orientation).");
        if (map.infinite)
            error("infinite maps aren't supported (Map > Map Properties > Infinite).");
        if (map.tileWidth !== P.TILE || map.tileHeight !== P.TILE)
            error("tiles must be " + P.TILE + "x" + P.TILE + ".");
        var autotiles = 0;
        map.tilesets.forEach(function (ts) {
            if (ts.className === "CharacterPreview")
                return;
            if (!ts.fileName)
                error("tileset " + ts.name + " is embedded; export it as a .tsj (Tileset > Export Tileset).");
            if (ts.tileWidth !== P.TILE || ts.tileHeight !== P.TILE)
                error("tileset " + ts.name + " must have " + P.TILE + "x" + P.TILE + " tiles.");
            if (ts.className === "Autotile")
                autotiles++;
        });
        if (autotiles > P.AUTOTILE_SLOTS)
            error("a map can use at most " + P.AUTOTILE_SLOTS + " autotiles (it has " + autotiles + ").");

        var layers = P.allLayers(map).filter(function (l) { return l.isTileLayer; });
        var counts = new Array(map.width * map.height);
        var flipped = 0, crowded = 0;
        layers.forEach(function (layer) {
            for (var y = 0; y < map.height; y++) {
                for (var x = 0; x < map.width; x++) {
                    var cell = layer.cellAt(x, y);
                    if (cell.tileId < 0)
                        continue;
                    var i = y * map.width + x;
                    counts[i] = (counts[i] || 0) + 1;
                    if (cell.flippedHorizontally || cell.flippedVertically || cell.flippedAntiDiagonally ||
                            cell.rotatedHexagonal120) {
                        flipped++;
                        if (flipped <= MAX_REPORTED)
                            error("layer " + layer.name + ", tile " + x + "," + y + ": flipped or rotated tiles " +
                                  "aren't supported.");
                    }
                }
            }
        });
        if (layers.length > P.RMXP_LAYERS) {
            for (var i = 0; i < counts.length; i++) {
                if (counts[i] > P.RMXP_LAYERS) {
                    crowded++;
                    if (crowded <= MAX_REPORTED)
                        error("tile " + (i % map.width) + "," + Math.floor(i / map.width) + ": " + counts[i] +
                              " tiles are stacked; RPG Maker XP maps hold at most 3.");
                }
            }
        }
        if (flipped > MAX_REPORTED)
            error("... and " + (flipped - MAX_REPORTED) + " more flipped tiles.");
        if (crowded > MAX_REPORTED)
            error("... and " + (crowded - MAX_REPORTED) + " more tiles with more than 3 stacked.");

        // Event ids: missing ones are assigned, duplicates (copies) renumbered.
        var events = P.events(map);
        var used = {}, max = 0;
        events.forEach(function (o) { max = Math.max(max, P.value(o.property("event_id")) || 0, o.id); });
        events.sort(function (a, b) { return a.id - b.id; }).forEach(function (o) {
            var id = P.value(o.property("event_id")) || 0;
            if (!id || used[id]) {
                var fresh = ++max;
                if (id)
                    tiled.warn(name + ": event " + o.name + " was a copy of event " + id +
                               "; it is now event " + fresh + ".", null);
                o.setProperty("event_id", fresh);
                id = fresh;
            }
            used[id] = true;
        });
        return problems;
    }

    function checkTileset(ts) {
        if (ts.className === "CharacterPreview")
            return 0;
        if (ts.tileWidth !== Pokessentials.TILE || ts.tileHeight !== Pokessentials.TILE) {
            tiled.error(ts.name + ": tiles must be " + Pokessentials.TILE + "x" + Pokessentials.TILE + ".", null);
            return 1;
        }
        return 0;
    }

    tiled.assetAboutToBeSaved.connect(function (asset) {
        try {
            if (typeof Pokessentials === "undefined" || !tiled.projectFilePath)
                return;
            if (asset.isTileMap) {
                for (var i = asset.layerCount - 1; i >= 0; i--) {
                    var layer = asset.layerAt(i);
                    if (layer.name === "~ Collision overlay")
                        asset.removeLayerAt(i);   // never saved (see TileData.js)
                }
                checkMap(asset);
            } else if (asset.isTileset) {
                checkTileset(asset);
            }
        } catch (e) {
            tiled.warn("Pokessentials validation: " + e, null);
        }
    });

    var validate = tiled.registerAction("PokessentialsValidate", function () {
        var r = Pokessentials.runTool(["validate"]);
        r.out.split("\n").forEach(function (line) {
            if (/^error:/.test(line))
                tiled.error(line, null);
            else if (/^warning:/.test(line))
                tiled.warn(line, null);
            else
                tiled.log(line);
        });
        tiled.alert(r.code === 0 ? r.out.split("\n").pop()
                                 : "Problems found; see the Issues panel.\n\n" + r.out.split("\n").slice(0, 15).join("\n"),
                    "Validate Project");
    });
    validate.text = "Validate Project";

    tiled.extendMenu("Map", [
        { action: "PokessentialsValidate" }
    ]);
})();
