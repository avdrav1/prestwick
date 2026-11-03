#!/usr/bin/env bash
# Headless checks for Prestwick: parse every script, load the main scene, run GUT.
#
#   scripts/run_tests.sh          the default run, under a minute (E2-S16)
#   scripts/run_tests.sh --full   the settle sweeps in tests/test_ball.gd at full density
#                                 (tests/fixtures/sweep.gd; for /balance surfaces and before a ship)
#   scripts/run_tests.sh --leaks  show Godot's exit-time leak report unfiltered (below)
#
# Known and harmless (E2-S16): Godot's exit-time leak report. Godot 4.7.2 leaks a few
# compiled GDScript objects at exit when a script names a class as a member's type and then
# reaches the same class's dependents through another class's member call. Smallest case
# found, in any script under res://:
#     var lies: LieTable
#     func f() -> void:
#         var m := ShotModel.new()
#         var c: Club = m.clubs.club("7i")
# leaks lie_table.gd, lie.gd, height_field.gd and surface.gd ("ObjectDB instances were leaked
# at exit", "resources still in use at exit"). The same line without the member, or with a
# ClubSet parameter in place of the ShotModel, does not. tests/test_lies.gd, test_ball.gd,
# test_shot_view.gd and test_sim.gd match it, under --check-only and under GUT alike; under
# GUT the leaked test script also holds GUT's own objects (its fonts, theme and text RIDs),
# so the report grows. What leaks is only script objects the process holds until it ends, at
# exit, with exit code 0; no game state, scene node or test result is involved (GUT reports
# orphan nodes on its own, per test). So those report lines are filtered out of the output,
# but only up to the counts recorded for each step in exit_leak_baseline below. A report above
# its baseline, or one from any other script, is printed whole with a LEAK line and fails the
# run (E6-S14), so a new leak (a reference cycle in game code, say) cannot pass unseen. A
# filtered report leaves one summary line with its counts. --leaks prints every report
# unfiltered and does not fail on them.
#
# Rechecking the baselines (after a Godot upgrade, after editing one of the four test scripts
# above, or when a run fails with LEAK and the cause is this bug rather than a new leak):
#   1. scripts/run_tests.sh --leaks
#   2. Check that every "leaked at exit" and "still in use at exit" block names only what this
#      bug explains (lie_table.gd, lie.gd, height_field.gd, surface.gd, the test script, and
#      under GUT its fonts, theme and RIDs). Anything else is a real leak: fix it, never raise
#      a baseline for it.
#   3. Set each step's "<objects> <resources>" in exit_leak_baseline to the counts printed. A
#      step whose report went away comes off the list; if every report is gone, Godot fixed
#      the bug, so remove quiet_exit_leaks, the baselines and this note.
#   4. Rerun without --leaks: it must pass, with a "filtered" line for each listed step.
set -euo pipefail
cd "$(dirname "$0")/.."

LEAKS=0
for arg in "$@"; do
  case "$arg" in
    --full) export PRESTWICK_FULL_SWEEPS=1 ;;
    --leaks) LEAKS=1 ;;
    *) echo "usage: scripts/run_tests.sh [--full] [--leaks]" >&2; exit 2 ;;
  esac
done

GODOT="${GODOT:-godot}"
if [ -x .bin/godot ]; then GODOT=.bin/godot; fi
if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "godot not found. Run scripts/install_godot.sh or set GODOT=/path/to/godot" >&2
  exit 2
fi

# The known exit-leak report per step, as "<ObjectDB instances> <resources in use>" maximums
# (measured on Godot 4.7.2, 2026-11-03). Anything not listed has a baseline of none.
exit_leak_baseline() {
  case "$1" in
    ./tests/test_lies.gd) echo "10 8" ;;
    ./tests/test_ball.gd) echo "9 7" ;;
    ./tests/test_shot_view.gd) echo "6 4" ;;
    ./tests/test_sim.gd) echo "107 36" ;;
    gut) echo "253 72" ;;
    *) echo "0 0" ;;
  esac
}

# Filters Godot's exit-time leak report for step $1 (a script path, or "gut") when it is within
# that step's baseline, leaving one summary line, and exits 0. A report above the baseline, or
# any leak line from a step with no baseline, is printed whole and exits 1 (E6-S14), so the
# caller fails the run. With --leaks it prints everything unfiltered and exits 0.
# The PagedAllocator and RID lines that follow a known report go with it.
quiet_exit_leaks() {
  if [ "$LEAKS" = 1 ]; then cat; return; fi
  local base
  base="$(exit_leak_baseline "$1")"
  awk -v step="$1" -v omax="${base% *}" -v rmax="${base#* }" '
    function count(line) { match(line, /[0-9]+/); return substr(line, RSTART, RLENGTH) + 0 }
    /ObjectDB instances were leaked at exit/ {
      objs = count($0)
      if (objs > omax) over = 1
      if (over) { print; next }
      known = 1; skip = 1; next
    }
    /resources still in use at exit/ {
      res = count($0)
      if (res > rmax || !known) over = 1
      if (over) { print; next }
      skip = 1; next
    }
    /Pages in use exist at exit in PagedAllocator|RID allocations of type .* were leaked at exit/ {
      if (!known) over = 1
      if (over) { print; next }
      skip = 1; next
    }
    skip && /^   at: / { skip = 0; next }
    { skip = 0; print }
    END {
      if (over) {
        printf "LEAK: the exit leak report for %s is above its known baseline (%d objects, %d resources), a new leak. See the header of scripts/run_tests.sh.\n", step, omax, rmax
        exit 1
      } else if (known) {
        printf "exit leak report for %s filtered: %d objects, %d resources (known, baseline %d/%d; --leaks shows it)\n", step, objs, res, omax, rmax
      }
    }
  '
}

# Parses one script. Fails on a non-zero exit or a leak over its baseline; prints whatever
# else Godot said.
check_one() {
  local f="$1" out rc=0 leak=0
  out="$("$GODOT" --headless --check-only -s "$f" 2>&1 >/dev/null)" || rc=$?
  out="$(printf '%s\n' "$out" | quiet_exit_leaks "$f")" || leak=1
  if [ -n "$out" ]; then printf '%s\n' "$out"; fi
  if [ "$rc" -ne 0 ]; then echo "parse error: $f"; return 1; fi
  if [ "$leak" -ne 0 ]; then echo "leak: $f"; return 1; fi
}

echo "== import"
# A fresh clone has no .godot/ class cache; class_name lookups fail until the project is imported once.
"$GODOT" --headless --path . --import >/dev/null 2>&1 || { echo "import failed"; exit 1; }

echo "== parse"
# One Godot per script, as many at once as there are cores (about 0.4 s each; 89 scripts took
# 38 s one at a time).
export GODOT LEAKS
export -f exit_leak_baseline quiet_exit_leaks check_one
JOBS="$(nproc 2>/dev/null || echo 4)"
find . -name '*.gd' -not -path './addons/*' -not -path './.bin/*' -not -path './.claude/*' -not -path './.godot/*' -print0 \
  | xargs -0 -n 1 -P "$JOBS" bash -c 'check_one "$1"' _ || { echo "parse failed (a parse error or a new leak above)"; exit 1; }

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

echo "== tests${PRESTWICK_FULL_SWEEPS:+ (full sweeps)}"
if [ -d addons/gut ]; then
  # pipefail keeps GUT's exit code through the filter, and the filter's own (a new leak).
  "$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1 | quiet_exit_leaks gut \
    || { echo "tests failed (a failing test, or a leak above the gut baseline)"; exit 1; }
else
  echo "GUT not installed (addons/gut). Skipping tests." >&2
  exit 3
fi
echo "== done in ${SECONDS} s"
