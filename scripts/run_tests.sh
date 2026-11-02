#!/usr/bin/env bash
# Headless checks for Prestwick: parse every script, load the main scene, run GUT.
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
if [ -x .bin/godot ]; then GODOT=.bin/godot; fi
if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "godot not found. Run scripts/install_godot.sh or set GODOT=/path/to/godot" >&2
  exit 2
fi

echo "== parse"
find . -name '*.gd' -not -path './addons/*' -not -path './.bin/*' | while read -r f; do
  "$GODOT" --headless --check-only -s "$f" >/dev/null || { echo "parse error: $f"; exit 1; }
done

echo "== scene"
if [ -f scenes/main.tscn ]; then
  "$GODOT" --headless --quit --path . scenes/main.tscn
fi

echo "== tests"
if [ -d addons/gut ]; then
  "$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
else
  echo "GUT not installed (addons/gut). Skipping tests." >&2
  exit 3
fi
