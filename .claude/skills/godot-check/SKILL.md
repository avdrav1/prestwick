---
name: godot-check
description: Run the headless Godot checks for Prestwick: script parse, scene load, GUT tests. Use before closing any story, before shipping, or when the user asks "does it build".
---

# Godot check

Runs `scripts/run_tests.sh`, which does three things in order and stops at the first failure:

1. **Parse.** `godot --headless --check-only -s <every .gd file>`. Any script error fails the run.
2. **Scenes.** `godot --headless --quit --path . scenes/main.tscn`. A scene that throws on `_ready` fails the run.
3. **Tests.** `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`. Any failing or pending GUT test fails the run.

## Steps

1. Run `bash scripts/run_tests.sh`.
2. On failure, read the first error, open the file and line it names, fix it, and rerun. Do not silence a test to make it pass.
3. On success, report the test count and runtime in one line.

## If godot is missing

Say so. Suggest `scripts/install_godot.sh` (downloads the pinned 4.3 headless binary to `.bin/`). Do not run it without asking; it downloads ~50 MB.

## Rules

- Never commit with this red.
- A new `.gd` file with logic needs a test in the same story.
