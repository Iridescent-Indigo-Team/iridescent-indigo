#!/bin/sh
#===============================================================================
# CreateEventSource.sh FILE [EVENT_NAME]
#-------------------------------------------------------------------------------
# Opens an event's command script (src/tiled/events/<map>/<id>_<name>.rb) in
# your text editor, creating it first if it doesn't exist. Called by the
# "Edit Event Script" action of the Tiled extension (CreateRPGEvent.js).
#
# The editor is $VISUAL or $EDITOR when set (a terminal editor needs a
# terminal, so a graphical one such as `code` is best), otherwise the
# system's default program for .rb files.
#===============================================================================
set -e
file="$1"
name="${2:-event}"
if [ -z "$file" ]; then
    echo "Usage: $0 FILE [EVENT_NAME]" >&2
    exit 2
fi
if [ ! -f "$file" ]; then
    mkdir -p "$(dirname "$file")"
    cat > "$file" <<RUBY
# Event "$name"
# Page settings are on the event's object in Tiled. See docs/TILED.md.

page 0, [
]
RUBY
fi
if [ -n "$VISUAL" ]; then
    exec $VISUAL "$file"
elif [ -n "$EDITOR" ]; then
    exec $EDITOR "$file"
elif command -v xdg-open >/dev/null 2>&1; then
    exec xdg-open "$file"
elif command -v open >/dev/null 2>&1; then
    exec open -t "$file"
fi
echo "No editor found; open $file yourself." >&2
exit 1
