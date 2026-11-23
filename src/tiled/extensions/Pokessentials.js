/**
 * @file Pokessentials.js
 * Shared helpers for the Pokessentials Tiled extensions (see docs/TILED.md).
 *
 * Tiled loads every .js file in this folder into one script engine, so the
 * other extensions reach these helpers through the global `Pokessentials`
 * object when their actions run. Needs Tiled 1.10 or newer.
 */

var Pokessentials = (function () {
    "use strict";

    /** Tile size of the sources, in pixels (the build halves it). */
    var TILE = 16;
    /** Tile layers an RPG Maker XP map holds per tile. */
    var RMXP_LAYERS = 3;
    /** Autotiles per map. */
    var AUTOTILE_SLOTS = 7;

    /**
     * Joins path parts with "/".
     * @param {...string} parts
     * @return {string}
     */
    function join() {
        var parts = Array.prototype.slice.call(arguments);
        return parts.join("/").replace(/\\/g, "/").replace(/\/+/g, "/");
    }

    /** @return {string} folder of a file path */
    function dirname(path) {
        path = path.replace(/\\/g, "/");
        return path.substring(0, path.lastIndexOf("/"));
    }

    /** @return {string} file name without folder and extension */
    function stem(path) {
        var name = path.replace(/\\/g, "/").split("/").pop();
        var dot = name.lastIndexOf(".");
        return dot > 0 ? name.substring(0, dot) : name;
    }

    /** @return {string} the src/tiled folder (where the project file is) */
    function srcDir() {
        if (tiled.projectFilePath)
            return dirname(tiled.projectFilePath);
        var asset = tiled.activeAsset;
        if (asset && asset.fileName)
            return dirname(dirname(asset.fileName));
        throw new Error("Open src/tiled/pokessentials.tiled-project first (Project > Open Project).");
    }

    /** @return {string} the repository root */
    function rootDir() {
        return dirname(dirname(srcDir()));
    }

    /** @return {string} a path relative to the folder of fromFile */
    function relative(path, fromFile) {
        var from = dirname(fromFile).replace(/\\/g, "/").split("/");
        var to = path.replace(/\\/g, "/").split("/");
        var i = 0;
        while (i < from.length && i < to.length && from[i] === to[i])
            i++;
        var up = [];
        for (var j = i; j < from.length; j++)
            up.push("..");
        return up.concat(to.slice(i)).join("/");
    }

    /** A file name made from an event or map name ("Item ball" -> "item_ball"). */
    function slug(name) {
        var s = String(name || "").toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
        return s || "event";
    }

    function pad3(n) {
        return ("000" + n).slice(-3);
    }

    /** @return {string|null} the content of a text file */
    function readText(path) {
        if (!File.exists(path))
            return null;
        var f = new TextFile(path, TextFile.ReadOnly);
        var text = f.readAll();
        f.close();
        return text;
    }

    /** Writes a text file (creating its folder). */
    function writeText(path, text) {
        File.makePath(dirname(path));
        var f = new TextFile(path, TextFile.WriteOnly);
        f.write(text);
        f.commit();
    }

    /**
     * Runs tools/importer/tiled/tiled_compiler.py.
     * @param {string[]} args
     * @return {{code: number, out: string}}
     */
    function runTool(args) {
        var programs = tiled.platform === "windows" ? ["python", "py", "python3"] : ["python3", "python"];
        var script = join(rootDir(), "tools/importer/tiled/tiled_compiler.py");
        for (var i = 0; i < programs.length; i++) {
            var p = new Process();
            p.workingDirectory = rootDir();
            var code = p.exec(programs[i], ["-I", script].concat(args));
            if (code === -2 || code === -1)    // program not found
                continue;
            return { code: code, out: (p.readStdOut() + p.readStdErr()).trim() };
        }
        return { code: -1, out: "Python 3 wasn't found. Install it (it also builds the game)." };
    }

    /** @return {TileMap|null} the active map, or null with a message */
    function activeMap() {
        var asset = tiled.activeAsset;
        if (!asset || !asset.isTileMap) {
            tiled.alert("Open a map first.");
            return null;
        }
        return asset;
    }

    /** Every layer of a map (including inside groups), bottom first. */
    function allLayers(container) {
        var result = [];
        for (var i = 0; i < container.layerCount; i++) {
            var layer = container.layerAt(i);
            result.push(layer);
            if (layer.isGroupLayer)
                result = result.concat(allLayers(layer));
        }
        return result;
    }

    function className(obj) {
        return obj.className !== undefined ? obj.className : obj.type;
    }

    /** @return {boolean} true for an Event object */
    function isEvent(obj) {
        return className(obj) === "Event";
    }

    /** Every event object of a map. */
    function events(map) {
        var result = [];
        allLayers(map).forEach(function (layer) {
            if (layer.isObjectLayer)
                layer.objects.forEach(function (o) { if (isEvent(o)) result.push(o); });
        });
        return result;
    }

    /** A property value as plain data (class values become objects). */
    function value(v) {
        if (v && typeof v === "object" && v.value !== undefined && v.typeName !== undefined)
            return v.value;
        return v;
    }

    /** @return {number} an event's id (event_id, or its object id) */
    function eventId(obj) {
        return value(obj.property("event_id")) || obj.id;
    }

    /** The map's "Events" object layer, created if needed. */
    function eventsLayer(map) {
        var found = null;
        allLayers(map).forEach(function (l) {
            if (!found && l.isObjectLayer && l.name === "Events")
                found = l;
        });
        if (!found) {
            found = new ObjectGroup("Events");
            map.addLayer(found);
        }
        return found;
    }

    /** Folder of a map's event scripts. */
    function eventsFolder(map) {
        return join(srcDir(), "events", stem(map.fileName));
    }

    /** Value of a class property, for setProperty. */
    function classValue(type, members) {
        if (tiled.propertyValue)
            return tiled.propertyValue(type, members || {});
        return members || {};
    }

    /** Tile position of an object (see tiledc/events.py object_tile). */
    function objectTile(obj) {
        var x = obj.x, y = obj.y;
        if (obj.tile) {
            x += obj.width / 2 - TILE / 2;
            y -= TILE;
        }
        return { x: Math.round(x / TILE), y: Math.round(y / TILE) };
    }

    return {
        TILE: TILE, RMXP_LAYERS: RMXP_LAYERS, AUTOTILE_SLOTS: AUTOTILE_SLOTS,
        join: join, dirname: dirname, stem: stem, srcDir: srcDir, rootDir: rootDir, relative: relative,
        slug: slug, pad3: pad3, readText: readText, writeText: writeText, runTool: runTool,
        activeMap: activeMap, allLayers: allLayers, className: className, isEvent: isEvent,
        events: events, value: value, eventId: eventId, eventsLayer: eventsLayer,
        eventsFolder: eventsFolder, classValue: classValue, objectTile: objectTile
    };
})();
