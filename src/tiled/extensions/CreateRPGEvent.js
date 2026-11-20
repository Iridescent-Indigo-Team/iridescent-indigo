/**
 * @file CreateRPGEvent.js
 * Event actions (Map menu > Events, and the object context menu):
 *   - New Event: an Event object on the selected tile (select a tile with the
 *     Rectangular Select tool first) with a new event id and its own script
 *     src/tiled/events/<map>/<id>_<name>.rb.
 *   - Add Event Page: adds page_N (an EventPage) to the selected event.
 *   - Edit Event Script: opens the selected event's .rb in your text editor
 *     (creating it first if needed; see CreateEventSource.sh/.bat).
 *   - Insert Event Command: appends a command to a page of the selected
 *     event's script, from a list of the common ones.
 *   - Show Event Graphics: shows each event with its first page's graphic
 *     (needs `make tiled-assets` for the previews).
 *   - Export Selected Events / Import Events: standalone .rb files, to share
 *     events between maps and projects.
 * Templates (src/tiled/templates/*.tx: item ball, door, sign, ...) are placed
 * with Tiled's own Insert Template tool from the Templates panel.
 */

(function () {
    "use strict";

    /** Commands offered by Insert Event Command: label -> Ruby snippet. */
    var COMMANDS = [
        ["Show Text", 'text("Hello!")'],
        ["Show Text (several lines)", 'text("First line", "second line")'],
        ["Show Choices", '*show_choices(\n  choices: ["Yes", "No"],\n  cancellation: 2,\n  choice1: [\n    text("Yes!"),\n  ],\n  choice2: [\n    text("No..."),\n  ],\n)'],
        ["Conditional Branch (script)", '*condition(\n  script: "$player.has_pokedex",\n  then: [\n    text("..."),\n  ],\n  else: [\n    text("..."),\n  ],\n)'],
        ["Conditional Branch (switch)", '*condition(\n  switch: s(1),\n  value: :ON,\n  then: [\n  ],\n)'],
        ["Control Switches", "control_switches(s(1), :ON)"],
        ["Control Self Switch", 'control_self_switch("A", :ON)'],
        ["Script", 'script("pbReceiveItem(:POTION)")'],
        ["Transfer Player (to a Spawn)", 'transfer(to: "Map name", spawn: "spawn name")'],
        ["Transfer Player (to a tile)", 'transfer(to: "Map name", x: 5, y: 5, direction: :down)'],
        ["Wild Battle", 'script("WildBattle.start(:PIKACHU, 5)")'],
        ["Trainer Battle", 'script("TrainerBattle.start(:YOUNGSTER, \\"Ben\\")")'],
        ["Give Item", 'script("pbReceiveItem(:POTION)")'],
        ["Move Route (this event)", "*move_route(\n  this,\n  move_down,\n  move_down,\n)"],
        ["Move Route (ignore sideways stairs)", "*move_route(\n  this,\n  stairs_off,\n  move_left,\n  stairs_on,\n)"],
        ["Wait for Move Completion", "wait_completion"],
        ["Wait", "wait(20)"],
        ["Play SE", 'play_se(audio(name: "Door exit"))'],
        ["Change Atmosphere layer", "atmosphere(:fog, opacity: 0, frames: 20)"],
        ["Comment", 'comment("Note")'],
        ["Exit Event Processing", "exit_event_processing"],
        ["Erase Event", "erase_event"]
    ];

    function selectedEvent(map) {
        var sel = map.selectedObjects.filter(Pokessentials.isEvent);
        if (sel.length !== 1) {
            tiled.alert("Select one event first.");
            return null;
        }
        return sel[0];
    }

    function scriptPath(map, obj) {
        var P = Pokessentials;
        var script = P.value(obj.property("script"));
        if (!script)
            return null;
        if (typeof script === "object" && script.url)
            script = script.url.toString().replace(/^file:\/\//, "");
        script = String(script);
        if (/^([a-zA-Z]:)?\//.test(script))
            return script;
        return P.join(P.dirname(map.fileName), script);
    }

    function setScript(map, obj, path) {
        obj.setProperty("script", tiled.filePath(path));
    }

    function nextEventId(map) {
        var max = 0;
        Pokessentials.events(map).forEach(function (o) { max = Math.max(max, Pokessentials.eventId(o)); });
        return max + 1;
    }

    function newScript(map, id, name) {
        var P = Pokessentials;
        var path = P.join(P.eventsFolder(map), P.pad3(id) + "_" + P.slug(name) + ".rb");
        if (!File.exists(path))
            P.writeText(path, "# Event " + id + " \"" + name + "\" on " + P.stem(map.fileName) + "\n" +
                        "# Page settings are on the event's object in Tiled. See docs/TILED.md.\n\n" +
                        "page 0, [\n]\n");
        return path;
    }

    var newEvent = tiled.registerAction("PokessentialsNewEvent", function () {
        var P = Pokessentials;
        var map = P.activeMap();
        if (!map)
            return;
        var x = 0, y = 0;
        var rect = map.selectedArea ? map.selectedArea.boundingRect : null;
        if (rect && rect.width > 0) {
            x = rect.x;
            y = rect.y;
        } else {
            var pos = tiled.prompt("Tile for the new event (x, y). Tip: select a tile with the " +
                                   "Rectangular Select tool first.", "0, 0", "New Event");
            if (!pos)
                return;
            var m = /(\d+)\D+(\d+)/.exec(pos);
            if (!m)
                return;
            x = parseInt(m[1], 10);
            y = parseInt(m[2], 10);
        }
        var name = tiled.prompt("Event name:", "EV" + P.pad3(nextEventId(map)), "New Event");
        if (name === "" || name === undefined || name === null)
            return;
        map.macro("New Event", function () {
            var id = nextEventId(map);
            var obj = new MapObject(MapObject.Rectangle, name);
            obj.className !== undefined ? (obj.className = "Event") : (obj.type = "Event");
            obj.x = x * P.TILE;
            obj.y = y * P.TILE;
            obj.width = P.TILE;
            obj.height = P.TILE;
            obj.setProperty("event_id", id);
            obj.setProperty("page_0", P.classValue("EventPage", {}));
            P.eventsLayer(map).addObject(obj);
            setScript(map, obj, newScript(map, id, name));
            map.selectedObjects = [obj];
        });
    });
    newEvent.text = "New Event...";

    var addPage = tiled.registerAction("PokessentialsAddPage", function () {
        var map = Pokessentials.activeMap();
        var obj = map && selectedEvent(map);
        if (!obj)
            return;
        var n = 0;
        while (obj.property("page_" + n) !== undefined)
            n++;
        obj.setProperty("page_" + n, Pokessentials.classValue("EventPage", {}));
        var path = scriptPath(map, obj);
        if (path && File.exists(path)) {
            var text = Pokessentials.readText(path);
            if (text.indexOf("page " + n + ",") < 0)
                Pokessentials.writeText(path, text.replace(/\s*$/, "\n") + "\npage " + n + ", [\n]\n");
        }
        tiled.log("Added page_" + n + " to event " + Pokessentials.eventId(obj));
    });
    addPage.text = "Add Event Page";

    var editScript = tiled.registerAction("PokessentialsEditScript", function () {
        var P = Pokessentials;
        var map = P.activeMap();
        var obj = map && selectedEvent(map);
        if (!obj)
            return;
        var path = scriptPath(map, obj);
        if (!path) {
            path = newScript(map, P.eventId(obj), obj.name);
            setScript(map, obj, path);
        }
        var tool = P.join(P.srcDir(), "extensions",
                          tiled.platform === "windows" ? "CreateEventSource.bat" : "CreateEventSource.sh");
        var p = new Process();
        var code = tiled.platform === "windows" ? p.exec("cmd", ["/c", tool, path, obj.name])
                                                : p.exec("sh", [tool, path, obj.name]);
        if (code !== 0)
            tiled.alert("Couldn't open " + path + ":\n" + p.readStdErr());
    });
    editScript.text = "Edit Event Script";

    var insertCommand = tiled.registerAction("PokessentialsInsertCommand", function () {
        var P = Pokessentials;
        var map = P.activeMap();
        var obj = map && selectedEvent(map);
        if (!obj)
            return;
        var path = scriptPath(map, obj);
        if (!path) {
            path = newScript(map, P.eventId(obj), obj.name);
            setScript(map, obj, path);
        }
        var list = COMMANDS.map(function (c, i) { return (i + 1) + ". " + c[0]; }).join("\n");
        var pick = tiled.prompt("Command to add (number):\n" + list, "1", "Insert Event Command");
        var index = parseInt(pick, 10) - 1;
        if (!(index >= 0 && index < COMMANDS.length))
            return;
        var page = parseInt(tiled.prompt("Add it to the end of page:", "0", "Insert Event Command"), 10);
        if (isNaN(page))
            return;
        var text = P.readText(path) || "";
        var snippet = COMMANDS[index][1].split("\n").map(function (l) { return "  " + l; }).join("\n") + ",\n";
        var empty = new RegExp("^page " + page + ", \\[\\]\\s*$", "m");
        var start = new RegExp("^page " + page + ", \\[\\s*$", "m");
        if (empty.test(text)) {
            text = text.replace(empty, "page " + page + ", [\n" + snippet + "]");
        } else if (start.test(text)) {
            var at = text.search(start);
            var close = text.indexOf("\n]", at);
            if (close < 0) {
                tiled.alert("Couldn't find the end of page " + page + " in " + path + ".");
                return;
            }
            text = text.substring(0, close + 1) + snippet + text.substring(close + 1);
        } else {
            text = text.replace(/\s*$/, "\n") + "\npage " + page + ", [\n" + snippet + "]\n";
        }
        P.writeText(path, text);
        tiled.log("Added \"" + COMMANDS[index][0] + "\" to page " + page + " of " + path);
    });
    insertCommand.text = "Insert Event Command...";

    var showGraphics = tiled.registerAction("PokessentialsShowGraphics", function () {
        var P = Pokessentials;
        var map = P.activeMap();
        if (!map)
            return;
        var tsjPath = P.join(P.srcDir(), "generated", "characters.tsj");
        if (!File.exists(tsjPath)) {
            tiled.alert("Run `make tiled-assets` first to make the event previews.");
            return;
        }
        var ts = null;
        map.tilesets.forEach(function (t) { if (t.fileName === tsjPath) ts = t; });
        if (!ts) {
            ts = tiled.open(tsjPath);
            map.addTileset(ts);
        }
        var byKey = {};
        ts.tiles.forEach(function (tile) {
            byKey[tile.property("graphic") + "|" + tile.property("direction")] = tile;
        });
        var shown = 0;
        map.macro("Show Event Graphics", function () {
            P.events(map).forEach(function (obj) {
                var page = P.value(obj.property("page_0")) || {};
                var tile = page.graphic ? byKey[page.graphic + "|" + (page.direction || "down")] : null;
                var pos = P.objectTile(obj);
                if (tile) {
                    obj.tile = tile;
                    obj.width = tile.width;
                    obj.height = tile.height;
                    obj.x = pos.x * P.TILE + P.TILE / 2 - tile.width / 2;
                    obj.y = (pos.y + 1) * P.TILE;
                    shown++;
                } else if (obj.tile) {
                    obj.tile = null;
                    obj.width = P.TILE;
                    obj.height = P.TILE;
                    obj.x = pos.x * P.TILE;
                    obj.y = pos.y * P.TILE;
                }
            });
        });
        tiled.log("Showing the graphics of " + shown + " events.");
    });
    showGraphics.text = "Show Event Graphics";

    var exportEvents = tiled.registerAction("PokessentialsExportEvents", function () {
        var P = Pokessentials;
        var map = P.activeMap();
        if (!map)
            return;
        var sel = map.selectedObjects.filter(P.isEvent);
        var out = tiled.prompt("Folder to export into:", P.join(P.rootDir(), "build", "events"), "Export Events");
        if (!out)
            return;
        var args = ["export-events", map.fileName, out];
        sel.forEach(function (o) { args.push("--event", String(P.eventId(o))); });
        var r = P.runTool(args);
        tiled.alert(r.out, "Export Events");
    });
    exportEvents.text = "Export Selected Events...";

    var importEvents = tiled.registerAction("PokessentialsImportEvents", function () {
        var P = Pokessentials;
        var map = P.activeMap();
        if (!map)
            return;
        if (map.modified) {
            tiled.alert("Save the map first: importing changes the saved file.");
            return;
        }
        var file = tiled.prompt("Exported event file (.rb) to add:", "", "Import Event");
        if (!file)
            return;
        var r = P.runTool(["import-events", map.fileName, file]);
        tiled.alert(r.out + (r.code === 0 ? "\n\nReopen the map to see it (File > Reload)." : ""), "Import Event");
    });
    importEvents.text = "Import Event...";

    tiled.extendMenu("Map", [
        { separator: true },
        { action: "PokessentialsNewEvent" },
        { action: "PokessentialsAddPage" },
        { action: "PokessentialsEditScript" },
        { action: "PokessentialsInsertCommand" },
        { action: "PokessentialsShowGraphics" },
        { action: "PokessentialsExportEvents" },
        { action: "PokessentialsImportEvents" }
    ]);
    try {
        tiled.extendMenu("MapView.Objects", [
            { action: "PokessentialsEditScript" },
            { action: "PokessentialsAddPage" },
            { action: "PokessentialsInsertCommand" }
        ]);
    } catch (e) {
        // Older Tiled versions have no object context menu to extend.
    }
})();
