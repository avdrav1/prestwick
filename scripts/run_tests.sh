#!/usr/bin/env bash
# Headless checks for Prestwick: parse every script, load the main scene, run GUT.
#
#   scripts/run_tests.sh          the default run, under a minute (E2-S16, E6-S22)
#   scripts/run_tests.sh --full   the heavy sweeps at full density (tests/fixtures/sweep.gd): the
#                                 settle sweeps in tests/test_ball.gd, the brute-force putts in
#                                 tests/test_shot_prediction.gd, the noisy chips in
#                                 tests/test_round_flow.gd and the hilly-hole club sweep in
#                                 tests/test_settle.gd (E6-S29); for /balance surfaces and before a ship
#   scripts/run_tests.sh --leaks  show Godot's exit-time leak report unfiltered (below)
#
# E6-S22: GUT runs one Godot per test script, as many at once as there are physical cores (TEST_JOBS
# overrides it; TEST_JOBS=1 runs them one at a time), so the wall time is about the slowest
# script's (tests/test_ball.gd), not the sum of all of them. Each script prints one line; a
# failing script prints its whole GUT log. Every script's log is kept in .godot/test_logs/
# (the gut.p measurements are there).
#
# E6-S30: steady under load. Tests that time themselves (they start with BestTime.later(self),
# tests/fixtures/best_time.gd) pass at once in the parallel batch and then run alone, one at a
# time, after it, so a busy machine cannot push them past their wall-clock limits. Each run has
# its own user:// folder (XDG_DATA_HOME in a temp folder, one per job), removed at exit. With
# --full, a test that names Sweep.part in its body runs as SWEEP_PARTS Godots at once, each a
# slice of its sweep. Jobs start longest first, by the last run's times.
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
# test_shot_view.gd and test_sim.gd match it under --check-only, and all but test_shot_view.gd
# under GUT too; under GUT the leaked test script also holds GUT's own objects (its fonts,
# theme and text RIDs), so the report grows. What leaks is only script objects the process holds until it ends, at
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
#   3. Set each step's "<objects> <resources>" in exit_leak_baseline to the counts printed
#      (a gut: step's report is in .godot/test_logs/<script>.log). A
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
# (measured on Godot 4.7.2, 2026-11-03; the gut: steps, one GUT run per test script, on
# 2026-11-04). Anything not listed has a baseline of none.
exit_leak_baseline() {
  case "$1" in
    ./tests/test_lies.gd) echo "10 8" ;;
    ./tests/test_ball.gd) echo "9 7" ;;
    ./tests/test_shot_view.gd) echo "6 4" ;;
    ./tests/test_sim.gd) echo "108 37" ;;
    gut:tests/test_lies.gd) echo "186 73" ;;
    gut:tests/test_ball.gd) echo "185 72" ;;
    gut:tests/test_sim.gd) echo "189 76" ;;
    *) echo "0 0" ;;
  esac
}

# Filters Godot's exit-time leak report for step $1 (a script path, or "gut:" and a test script) when it is within
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

# E6-S30: each run has its own user:// (Godot's is $XDG_DATA_HOME/godot/app_userdata/Prestwick
# on Linux), and each GUT job its own folder in it, so test files and Godot's own logs never
# meet another job's, another worktree's run or the game's real saves. Removed at exit.
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/prestwick-tests.XXXXXX")"
trap 'rm -rf "$RUN_DIR"' EXIT
export PRESTWICK_TEST_RUN_DIR="$RUN_DIR"
export XDG_DATA_HOME="$RUN_DIR/shared"

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

# Runs one GUT job in its own Godot, with its own user:// folder: $1 is a test script
# (tests/test_x.gd), a script and one of its tests (tests/test_x.gd:test_name: --full's split
# and the timed tests, below), or one part of a parted test (tests/test_x.gd:test_name@k/n,
# PRESTWICK_SWEEP_PART=k/n, tests/fixtures/sweep.gd). $2 is the phase, "batch" or "timed"
# (PRESTWICK_TEST_PHASE=batch passes the timed tests at once, tests/fixtures/best_time.gd).
# Its filtered log goes to $TEST_LOGS/<phase>/<job>.log and one result line ("ok"/"FAIL",
# job, passing, tests, asserts, seconds) to <job>.result, read back once every job is done.
gut_one() {
  local spec="$1" phase="$2" f="${1%%:*}" test="" part="" job dir log rc=0 leak=0 start
  case "$spec" in *:*) test="${spec#*:}" ;; esac
  case "$test" in *@*) part="${test#*@}"; test="${test%@*}" ;; esac
  job="$(basename "$f" .gd)${test:+.$test}${part:+.part${part%/*}}"
  dir="$TEST_LOGS/$phase"
  log="$dir/$job.log"
  start="$(date +%s%N)"
  mkdir -p "$RUN_DIR/$phase/$job"
  XDG_DATA_HOME="$RUN_DIR/$phase/$job" PRESTWICK_TEST_PHASE="${phase/timed/}" \
    PRESTWICK_SWEEP_PART="$part" \
    "$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd -gtest="res://$f" ${test:+-gunit_test_name="$test"} \
    -gexit </dev/null >"$log.raw" 2>&1 || rc=$?
  quiet_exit_leaks "gut:$f" <"$log.raw" >"$log" || leak=1
  rm -f "$log.raw"
  awk -v name="$spec" -v single="${test:+1}" -v rc="$rc" -v leak="$leak" -v ms="$(( ($(date +%s%N) - start) / 1000000 ))" '
    { gsub(/\033\[[0-9;]*m/, "") }
    /^Tests +[0-9]+/ { tests = $2 }
    /^Passing Tests +[0-9]+/ { passing = $3 }
    /^Asserts +[0-9]+/ { asserts = $2 }
    END {
      ok = (rc == 0 && leak == 0 && tests > 0 && passing == tests)
      # A split job runs exactly one test: a name that is part of another would run both.
      if (single && tests != 1) { ok = 0; print "split job " name " ran " tests " tests, not 1: rename one" > "/dev/stderr" }
      printf "%s %s %d %d %d %.1f\n", ok ? "ok" : "FAIL", name, passing, tests, asserts, ms / 1000
    }' "$log" >"$dir/$job.result"
}

# Prints one line per script of the result lines on stdin (a split script's jobs summed, its
# time its slowest job's), then each failing job's log; returns 1 if any job failed.
report() {
  local phase="$1" results status name rest job failed=0
  results="$(sort -k2)"
  awk '!NF { next }
       { split($2, j, ":"); f = j[1]
         if (!(f in st)) { order[++n] = f; st[f] = "ok" }
         if ($1 != "ok") st[f] = "FAIL"
         p[f] += $3; t[f] += $4; a[f] += $5; if ($6 + 0 > sec[f] + 0) sec[f] = $6 }
       END { for (i = 1; i <= n; i++) { f = order[i]
               printf "%-4s %-34s %4d/%-4d passed %7d asserts %6.1f s\n", st[f], f, p[f], t[f], a[f], sec[f] } }' <<<"$results"
  while read -r status name rest; do
    [ -n "$status" ] || continue
    if [ "$status" != ok ]; then
      failed=1
      job="${name%%:*}"; job="$(basename "$job" .gd)"
      case "$name" in *:*) local t="${name#*:}"; job="$job.${t%@*}"; case "$t" in *@*) local k="${t#*@}"; job="$job.part${k%/*}" ;; esac ;; esac
      echo "---- FAIL $name ($TEST_LOGS/$phase/$job.log)"
      cat "$TEST_LOGS/$phase/$job.log"
      echo "----"
    fi
  done <<<"$results"
  return "$failed"
}

echo "== tests${PRESTWICK_FULL_SWEEPS:+ (full sweeps)}"
if [ ! -d addons/gut ]; then
  echo "GUT not installed (addons/gut). Skipping tests." >&2
  exit 3
fi
TEST_LOGS=.godot/test_logs
# The last run's job times, so the slowest jobs start first (below).
last_times="$RUN_DIR/last_times"
cat "$TEST_LOGS"/batch/*.result 2>/dev/null | awk '{ print $2, $6 }' >"$last_times" || true
rm -rf "$TEST_LOGS"
mkdir -p "$TEST_LOGS/batch" "$TEST_LOGS/timed"
export TEST_LOGS RUN_DIR
export -f gut_one

# The test functions (script:name) whose own body matches $1.
tests_naming() {
  awk -v pat="$1" '
    /^func / { name = ""; if ($0 ~ /^func test_/) { name = $2; sub(/\(.*/, "", name) } }
    name != "" && $0 ~ pat { key = FILENAME ":" name; if (!(key in seen)) { seen[key] = 1; print key } }
  ' tests/test_*.gd
}
# E6-S30: tests that time themselves against wall-clock limits start with BestTime.later(self)
# (tests/fixtures/best_time.gd): the parallel batch passes them at once, and they run after it,
# one at a time, so neither the other jobs nor other work on the machine (a playtest beside the
# run) can slow them past their limits.
TIMED="$(tests_naming '^[[:space:]]*if BestTime[.]later[(]self[)]')"
# With --full, the scripts whose sweeps run for minutes run one Godot per test (GUT's
# -gunit_test_name matches a substring; no test name in them is part of another), so the wall
# time is about the slowest test's. Every other script runs in one Godot. E6-S30: a test that
# names Sweep.part in its own body runs as SWEEP_PARTS Godots at once, each a slice of its
# sweep (tests/fixtures/sweep.gd), so no one sweep bounds the run.
FULL_SPLIT="tests/test_ball.gd tests/test_round_flow.gd tests/test_shot_prediction.gd tests/test_settle.gd"
SWEEP_PARTS=4
PARTED="$(tests_naming 'Sweep[.]part[^_A-Za-z0-9]')"
jobs_file="$TEST_LOGS/jobs"
for f in $(find tests -maxdepth 1 -name 'test_*.gd' -printf '%s %p\n' | sort -rn | cut -d' ' -f2-); do
  if [ -n "${PRESTWICK_FULL_SWEEPS:-}" ] && { [[ " $FULL_SPLIT " == *" $f "* ]] || grep -q "^$f:" <<<"$PARTED"; }; then
    for t in $(grep -o '^func test_[A-Za-z0-9_]*' "$f" | cut -c6-); do
      if grep -qx "$f:$t" <<<"$PARTED"; then
        for ((k = 0; k < SWEEP_PARTS; k++)); do echo "$f:$t@$k/$SWEEP_PARTS"; done
      else
        echo "$f:$t"
      fi
    done
  else
    echo "$f"
  fi
done >"$jobs_file.all"
# Longest first, by the last run's times (a job it did not have goes first, biggest script
# first), so the slowest jobs start at once and do not finish alone at the end.
awk 'FILENAME == ARGV[1] { t[$1] = $2; next } { print (($0 in t) ? t[$0] : 1e9), FNR, $0 }' \
  "$last_times" "$jobs_file.all" | sort -k1,1gr -k2,2n | cut -d' ' -f3- >"$jobs_file"
# One job per physical core, not per hardware thread: two jobs sharing a core run each at
# about half speed.
if [ "$(grep -c . "$jobs_file" || true)" -ne "$(grep -c . "$jobs_file.all" || true)" ] || ! grep -q . "$jobs_file"; then
  echo "no test jobs, or the longest-first order lost some (see $jobs_file.all)"
  exit 1
fi
GUT_JOBS="$( (lscpu -p=CORE,SOCKET 2>/dev/null || true) | grep -v '^#' | sort -u | grep -c . || true)"
if [ "${GUT_JOBS:-0}" -lt 1 ]; then GUT_JOBS="$JOBS"; fi
xargs -n 1 -P "${TEST_JOBS:-$GUT_JOBS}" bash -c 'gut_one "$1" batch' _ <"$jobs_file" || true
failed=0
results="$(cat "$TEST_LOGS"/batch/*.result 2>/dev/null)" || true
if [ "$(grep -c . <<<"$results")" -ne "$(grep -c . "$jobs_file")" ]; then
  echo "only $(grep -c . <<<"$results") of $(grep -c . "$jobs_file") test jobs reported a result (see $TEST_LOGS/batch)"
  failed=1
fi
report batch <<<"$results" || failed=1

timed_count="$(grep -c . <<<"$TIMED" || true)"
echo "== timed tests, one at a time ($timed_count)"
timed_results=""
if [ "$timed_count" -gt 0 ]; then
  while read -r spec; do gut_one "$spec" timed; done <<<"$TIMED"
  timed_results="$(cat "$TEST_LOGS"/timed/*.result 2>/dev/null)" || true
  if [ "$(grep -c . <<<"$timed_results")" -ne "$timed_count" ]; then
    echo "only $(grep -c . <<<"$timed_results") of $timed_count timed tests reported a result (see $TEST_LOGS/timed)"
    failed=1
  fi
  report timed <<<"$timed_results" || failed=1
fi

grep -h '^exit leak report for gut:' "$TEST_LOGS"/*/*.log | sort -u || true
# The batch passed each timed test at once (counted there), so a timed test counts as passed
# only if its own run passed.
awk -v timed="$timed_count" 'FNR == 1 { file++ } !NF { next }
     file == 1 { n++; p += $3; t += $4; a += $5 } file == 2 { p += $3 - 1; a += $5 }
     END { printf "%d jobs, then %d timed: %d/%d tests passed, %d asserts\n", n, timed, p, t, a }' \
  <(printf '%s\n' "$results") <(printf '%s\n' "$timed_results")
if [ "$failed" -ne 0 ]; then
  echo "tests failed (a failing test, or a leak above that script's gut: baseline, above)"
  exit 1
fi
echo "== done in ${SECONDS} s"
