/**
 * @file TileData.js
 * Tile data: passage, priority, terrain tag (surf, grass, ledges, ...), bush
 * and counter flags, stored on tiles as the "TileData" property (edit it in
 * the tileset editor; select many tiles to change them together).
 *
 *   - Show Collision Overlay (Map menu): draws a temporary layer over the
 *     map marking sideways stairs (pink), blocked tiles (red), one-way tiles
 *     (orange), water you can surf (blue), ledges (yellow), grass (green),
 *     counters (purple) and bushes (teal). Toggle it off again, or save: it's
 *     never saved.
 *   - Export Tile Data / Import Tile Data (Tileset menu): to and from .json,
 *     .csv or an RPG Maker XP Tilesets.rxdata, through tiled_compiler.py.
 */

(function () {
    "use strict";

    var OVERLAY = "~ Collision overlay";
    /** Overlay categories: name, colour, test on the tile data. */
    var CATEGORIES = [
        // First, so stair tiles with one-way passage still show as stairs.
        ["Stairs", "#c0f040c0", function (d) { return /^Stairs(Left|Right)$/.test(d.terrain_tag || ""); }],
        ["Blocked", "#c0e02020", function (d) { return d.block_down && d.block_left && d.block_right && d.block_up; }],
        ["One-way", "#c0f08020", function (d) { return d.block_down || d.block_left || d.block_right || d.block_up; }],
        ["Surf", "#a02060f0", function (d) { return /Water|Waterfall/.test(d.terrain_tag || ""); }],
        ["Ledge", "#c0f0e020", function (d) { return d.terrain_tag === "Ledge"; }],
        ["Grass", "#a020c040", function (d) { return /Grass/.test(d.terrain_tag || ""); }],
        ["Counter", "#c0a040e0", function (d) { return d.counter; }],
        ["Bush", "#a020c0c0", function (d) { return d.bush; }]
    ];

    function tileData(tile) {
        var P = Pokessentials;
        var data = {};
        var base = P.value(tile.tileset.property("TileData"));
        var own = P.value(tile.property("TileData"));
        [base, own].forEach(function (src) {
            if (!src)
                return;
            for (var k in src)
                data[k] = P.value(src[k]);
        });
        return data;
    }

    function removeOverlay(map) {
        for (var i = map.layerCount - 1; i >= 0; i--) {
            if (map.layerAt(i).name === OVERLAY) {
                map.removeLayerAt(i);
                return true;
            }
        }
        return false;
    }

    var overlay = tiled.registerAction("PokessentialsCollisionOverlay", function () {
        var P = Pokessentials;
        var map = P.activeMap();
        if (!map)
            return;
        if (removeOverlay(map))
            return;
        var group = new GroupLayer(OVERLAY);
        var layers = {};
        CATEGORIES.forEach(function (c) {
            var l = new ObjectGroup(c[0]);
            l.color = c[1];
            l.locked = true;
            layers[c[0]] = l;
            group.addLayer(l);
        });
        var tileLayers = P.allLayers(map).filter(function (l) { return l.isTileLayer; });
        for (var y = 0; y < map.height; y++) {
            for (var x = 0; x < map.width; x++) {
                // Like the game: the top tile with data decides.
                var found = null;
                for (var i = tileLayers.length - 1; i >= 0 && !found; i--) {
                    var tile = tileLayers[i].tileAt(x, y);
                    if (!tile)
                        continue;
                    var d = tileData(tile);
                    if (d.block_down || d.block_left || d.block_right || d.block_up || d.terrain_tag || d.bush ||
                            d.counter || d.priority)
                        found = d;
                }
                if (!found)
                    continue;
                for (var c = 0; c < CATEGORIES.length; c++) {
                    if (CATEGORIES[c][2](found)) {
                        var o = new MapObject(MapObject.Rectangle, "");
                        o.x = x * P.TILE + 2;
                        o.y = y * P.TILE + 2;
                        o.width = P.TILE - 4;
                        o.height = P.TILE - 4;
                        layers[CATEGORIES[c][0]].addObject(o);
                        break;
                    }
                }
            }
        }
        group.opacity = 0.7;
        map.addLayer(group);
    });
    overlay.text = "Show Collision Overlay";
    overlay.checkable = false;

    function activeTileset() {
        var asset = tiled.activeAsset;
        if (!asset || !asset.isTileset || !asset.fileName) {
            tiled.alert("Open a saved tileset (.tsj) first.");
            return null;
        }
        if (asset.modified) {
            tiled.alert("Save the tileset first.");
            return null;
        }
        return asset;
    }

    var exportData = tiled.registerAction("PokessentialsExportTileData", function () {
        var ts = activeTileset();
        if (!ts)
            return;
        var P = Pokessentials;
        var out = tiled.prompt("Write the tile data to (.json or .csv):",
                               P.join(P.rootDir(), "build", P.stem(ts.fileName) + "_tiledata.csv"), "Export Tile Data");
        if (!out)
            return;
        var r = P.runTool(["export-tiledata", ts.fileName, out]);
        tiled.alert(r.out, "Export Tile Data");
    });
    exportData.text = "Export Tile Data...";

    var importData = tiled.registerAction("PokessentialsImportTileData", function () {
        var ts = activeTileset();
        if (!ts)
            return;
        var P = Pokessentials;
        var src = tiled.prompt("Read tile data from (.json, .csv or Tilesets.rxdata):", "", "Import Tile Data");
        if (!src)
            return;
        var args = ["import-tiledata", ts.fileName, src];
        if (/\.rxdata$/i.test(src)) {
            var id = tiled.prompt("RPG Maker XP tileset id:", "1", "Import Tile Data");
            if (!id)
                return;
            args.push("--tileset-id", id);
        }
        var r = P.runTool(args);
        tiled.alert(r.out + (r.code === 0 ? "\n\nReload the tileset to see the changes (File > Reload)." : ""),
                    "Import Tile Data");
    });
    importData.text = "Import Tile Data...";

    tiled.extendMenu("Map", [
        { action: "PokessentialsCollisionOverlay" }
    ]);
    tiled.extendMenu("Tileset", [
        { separator: true },
        { action: "PokessentialsExportTileData" },
        { action: "PokessentialsImportTileData" }
    ]);
})();
