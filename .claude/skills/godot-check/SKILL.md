---
name: godot-check
description: Run the headless Godot checks for Prestwick: script parse, scene load, GUT tests. Use before closing any story, before shipping, or when the user asks "does it build".
---

# Godot check

Runs `scripts/run_tests.sh`, which does three things in order and stops at the first failure:

1. **Parse.** `godot --headless --check-only -s <every .gd file>`, one per core at once. Any script error fails the run. Godot's exit-time leak report is known and harmless and is filtered to one summary line while it stays within its recorded per-step baseline (explained in `scripts/run_tests.sh`); a report above the baseline, or from any other script, is printed whole with a warning: treat that as a new leak. `--leaks` shows it unfiltered.
2. **Scenes.** `godot --headless --quit --path . scenes/main.tscn`. A scene that throws on `_ready` fails the run.
3. **Tests.** `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/<script> -gexit`, one Godot per test script, as many at once as there are physical cores (E6-S22; `TEST_JOBS=1` runs them one at a time). Each script prints one line; a failing one prints its whole GUT log. Every log is kept in `.godot/test_logs/`, with the `gut.p` measurements. Any failing GUT test fails the run.

The default run takes under a minute (E2-S16, E6-S22; 42 s measured 2026-11-04 on 12 cores (24 threads), about the time of `tests/test_ball.gd` alone): the settle sweeps in `tests/test_ball.gd` keep their worst starts and a few depths, and every D16 and D31 guard runs. `bash scripts/run_tests.sh --full` runs the heavy sweeps at full density: the settle sweeps, the noisy-chip grid in `tests/test_round_flow.gd` and the brute-force nearest putts in `tests/test_shot_prediction.gd`; those three scripts then run one Godot per test. Measured 2026-11-04 on 12 cores (24 threads): about 2.5 minutes (146 s), most of it the full noisy-chip grid, one test of about 100 s. Run it after a `/balance surfaces` change to `golf/ball.gd` or `course/surfaces.tres`, after a change to the putter's physics or `PuttAim` (a moved pinned putt in the default run also sends you there), and before `/ship-it`.

## Steps

1. Run `bash scripts/run_tests.sh`.
2. On failure, read the first error, open the file and line it names, fix it, and rerun. Do not silence a test to make it pass.
3. On success, report the test count and runtime in one line.

## If godot is missing

Say so. Suggest `scripts/install_godot.sh` (downloads the pinned 4.7.2 binary to `.bin/`). Do not run it without asking; it downloads ~50 MB.

## Rules

- Never commit with this red.
- A new `.gd` file with logic needs a test in the same story.
