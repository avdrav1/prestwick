#!/usr/bin/env bash
# Runs scripts/e4_playtest.gd (the scripted E4 checklist) at a fixed 60 fps with a throwaway
# user:// folder, so its save, load, autosave and settings never touch the player's own files
# ($XDG_DATA_HOME/godot/app_userdata/Prestwick). Extra arguments go to the script, e.g.
#   scripts/e4_playtest.sh --seed 1
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
if [ -x .bin/godot ]; then GODOT=.bin/godot; fi
DATA="$(mktemp -d)"
trap 'rm -rf "$DATA"' EXIT
export XDG_DATA_HOME="$DATA"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || { echo "import failed" >&2; exit 1; }
exec "$GODOT" --headless --path . --fixed-fps 60 -s res://scripts/e4_playtest.gd -- "$@"
