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

echo "== import"
# A fresh clone has no .godot/ class cache; class_name lookups fail until the project is imported once.
"$GODOT" --headless --path . --import >/dev/null 2>&1 || { echo "import failed"; exit 1; }

echo "== parse"
find . -name '*.gd' -not -path './addons/*' -not -path './.bin/*' -not -path './.claude/*' -not -path './.godot/*' | while read -r f; do
  "$GODOT" --headless --check-only -s "$f" >/dev/null || { echo "parse error: $f"; exit 1; }
done

echo "== scene"
if [ -f scenes/main.tscn ]; then
  # Godot exits 0 even when _ready throws, so fail on any error it prints.
  scene_out="$("$GODOT" --headless --quit --path . scenes/main.tscn 2>&1)" || { echo "$scene_out"; exit 1; }
  if grep -qE '^(SCRIPT )?ERROR' <<<"$scene_out"; then
    echo "$scene_out" | grep -E -A2 '^(SCRIPT )?ERROR'
    echo "scene error: scenes/main.tscn"
    exit 1
  fi
fi

echo "== tests"
if [ -d addons/gut ]; then
  "$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
else
  echo "GUT not installed (addons/gut). Skipping tests." >&2
  exit 3
fi
