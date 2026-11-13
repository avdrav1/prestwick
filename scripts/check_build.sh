#!/usr/bin/env bash
# Launch an exported Linux build headless for a few seconds and fail if it does not boot
# cleanly: non-zero exit, any ERROR or WARNING line (a missing course file warns), or the
# main scene never loading. Used by /ship-it after the Linux export.
#
# Official export templates refuse --script, so the scripted smoke (scripts/playtest.sh)
# runs on the project; this proves the exported pack carries a game that starts.
#
# Usage: scripts/check_build.sh <build/prestwick-*-linux.x86_64> [frames]
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: scripts/check_build.sh <exported-binary> [frames]" >&2
  exit 2
fi
bin="$1"
frames="${2:-300}"
[ -x "$bin" ] || { echo "not an executable build: $bin" >&2; exit 2; }

# A throwaway user:// (E13-S5): the game copies the example courses into its course folder at
# start, and its autosave writes there too; neither may touch the player's own folder.
BUILD_DATA="$(mktemp -d)"
trap 'rm -rf "$BUILD_DATA"' EXIT
export XDG_DATA_HOME="$BUILD_DATA"

status=0
out="$(timeout 60 "$bin" --headless --verbose --quit-after "$frames" 2>&1)" || status=$?
if [ "$status" -ne 0 ]; then
  echo "$out" | tail -20 >&2
  echo "build exited with $status: $bin" >&2
  exit 1
fi
if grep -qE '^(SCRIPT )?(ERROR|WARNING)' <<<"$out"; then
  grep -E -A2 '^(SCRIPT )?(ERROR|WARNING)' <<<"$out" >&2
  echo "build printed errors: $bin" >&2
  exit 1
fi
if ! grep -q "Completed load for: 'res://scenes/main.tscn'" <<<"$out"; then
  echo "build never loaded scenes/main.tscn: $bin" >&2
  exit 1
fi
echo "$(grep -m1 '^Godot Engine' <<<"$out")"
echo "build ok: $bin booted scenes/main.tscn and quit cleanly after $frames frames"
