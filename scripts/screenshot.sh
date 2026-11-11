#!/usr/bin/env bash
# Screenshot one scene: opens a real Godot window (a display is required; --headless
# draws no pixels and xvfb-run is not installed), waits a few frames, saves the viewport
# to a PNG, prints its path and quits. A window flashes briefly.
#
# Usage: scripts/screenshot.sh <scene> [out.png] [frames]
#   scene   res://scenes/main.tscn or a path relative to the repo (scenes/main.tscn)
#   out     default build/screenshots/<scene>_<timestamp>.png
#   frames  frames to wait before capturing, default 10
set -euo pipefail
cd "$(dirname "$0")/.."

if [ $# -lt 1 ]; then
  echo "usage: scripts/screenshot.sh <scene> [out.png] [frames]" >&2
  exit 2
fi

GODOT="${GODOT:-godot}"
if [ -x .bin/godot ]; then GODOT=.bin/godot; fi
# A throwaway user:// so a fixture never writes the player's saves or settings.
SHOT_DATA="$(mktemp -d)"
trap 'rm -rf "$SHOT_DATA"' EXIT
export XDG_DATA_HOME="$SHOT_DATA"
if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "godot not found. Run scripts/install_godot.sh or set GODOT=/path/to/godot" >&2
  exit 2
fi
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
  echo "no display (DISPLAY and WAYLAND_DISPLAY unset); screenshots need a real window" >&2
  exit 2
fi

scene="$1"
case "$scene" in
  res://*) ;;
  *) scene="res://${scene#./}" ;;
esac
file="${scene#res://}"
if [ ! -f "$file" ]; then
  echo "scene not found: $file" >&2
  exit 2
fi

name="$(basename "$file" .tscn)"
out="${2:-build/screenshots/${name}_$(date +%Y%m%d-%H%M%S).png}"
frames="${3:-10}"
mkdir -p "$(dirname "$out")"
out_abs="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"
rm -f "$out_abs"

# New or changed PNGs must be imported before the scene can load them.
"$GODOT" --headless --path . --import >/dev/null 2>&1 || { echo "import failed" >&2; exit 1; }

log="$("$GODOT" --path . -s res://scripts/screenshot.gd -- --scene="$scene" --out="$out_abs" --frames="$frames" 2>&1)" || {
  echo "$log" >&2
  exit 1
}
if grep -qE '^(SCRIPT )?ERROR' <<<"$log" || [ ! -s "$out_abs" ]; then
  echo "$log" >&2
  echo "screenshot failed: $scene" >&2
  exit 1
fi
echo "$out_abs"
