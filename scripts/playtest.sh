#!/usr/bin/env bash
# The /playtest smoke run: drives the main scene headless with scripts/playtest.gd and
# fails on any failed check or any error or warning Godot prints. Used by /ship-it.
#
# Usage: scripts/playtest.sh
# Runs the project in this repo with the editor binary. Official export templates refuse
# --script, so an exported build is checked with scripts/check_build.sh instead.
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
if [ -x .bin/godot ]; then GODOT=.bin/godot; fi
if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "godot not found. Run scripts/install_godot.sh or set GODOT=/path/to/godot" >&2
  exit 2
fi
# A fresh clone has no .godot/ class cache; class_name lookups fail until imported once.
"$GODOT" --headless --path . --import >/dev/null 2>&1 || { echo "import failed" >&2; exit 1; }
# The smoke saves, loads and writes settings: give it a throwaway user:// so it never touches
# the player's own saves, autosaves or settings ($XDG_DATA_HOME/godot/app_userdata/Prestwick).
PLAYTEST_DATA="$(mktemp -d)"
trap 'rm -rf "$PLAYTEST_DATA"' EXIT
export XDG_DATA_HOME="$PLAYTEST_DATA"
cmd=("$GODOT" --headless --path . --fixed-fps 60 -s res://scripts/playtest.gd)

status=0
out="$("${cmd[@]}" 2>&1)" || status=$?
echo "$out" | grep -vE '^(Godot Engine v|$)' || true
# Godot can print a script error and still exit 0, so an error line fails the smoke too.
# A warning fails it as well, the same bar as check_build.sh: a missing course file only
# warns and falls back to a flat plot.
if grep -qE '^(SCRIPT )?(ERROR|WARNING)' <<<"$out"; then
  echo "playtest smoke: errors or warnings printed" >&2
  exit 1
fi
if [ "$status" -ne 0 ] || ! grep -q '^playtest smoke: PASS' <<<"$out"; then
  exit 1
fi
