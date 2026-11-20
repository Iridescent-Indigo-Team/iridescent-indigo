/**
 * @file CreateRPGMap.js
 * Map actions (Map menu):
 *   - New Pokessentials Map: registers a map id in src/tiled/maps/registry.json,
 *     creates a fixed-size, orthogonal, 32px map with three tile layers, an
 *     "Events" layer and an "Atmosphere" group, and adds it to the world so
 *     it can be placed next to other maps (map connections).
 *   - Build Game Data: compiles src/tiled into build/ (same as `make tiled`).
 * Map metadata, encounters, music and atmosphere are the map's properties
 * (class "Map"), edited in the Properties panel.
 */

(function () {
    "use strict";

    var newMap = tiled.registerAction("PokessentialsNewMap", function () {
        var P = Pokessentials;
        var name = tiled.prompt("Name of the new map:", "", "New Pokessentials Map");
        if (!name)
            return;
        var size = tiled.prompt("Size in tiles (width x height):", "20x15", "New Pokessentials Map");
        if (!size)
            return;
        var m = /^\s*(\d+)\s*[x, ]\s*(\d+)\s*$/i.exec(size);
        if (!m) {
            tiled.alert("Write the size as width x height, like 20x15.");
            return;
        }
        var args = ["new-map", name, "--width", m[1], "--height", m[2]];
        var current = tiled.activeAsset;
        if (current && current.isTileMap && current.tilesets.length > 0 &&
                tiled.confirm("Use the same tilesets as " + P.stem(current.fileName) + "?")) {
            current.tilesets.forEach(function (ts) {
                if (ts.fileName && ts.className !== "CharacterPreview")
                    args.push("--tileset", ts.fileName);
            });
        }
        var result = P.runTool(args);
        if (result.code !== 0) {
            tiled.alert(result.out, "New Pokessentials Map");
            return;
        }
        var created = /Created (.*)\.\s*$/.exec(result.out);
        if (created)
            tiled.open(P.join(P.rootDir(), created[1]));
        tiled.log(result.out);
    });
    newMap.text = "New Pokessentials Map...";

    var build = tiled.registerAction("PokessentialsBuild", function () {
        var result = Pokessentials.runTool(["build"]);
        tiled.log(result.out);
        if (result.code !== 0)
            tiled.alert(result.out.split("\n").slice(-25).join("\n"), "Build Game Data failed");
        else
            tiled.alert(result.out.split("\n").slice(-5).join("\n"), "Build Game Data");
    });
    build.text = "Build Game Data";

    tiled.extendMenu("Map", [
        { separator: true },
        { action: "PokessentialsNewMap" },
        { action: "PokessentialsBuild" }
    ]);
})();
