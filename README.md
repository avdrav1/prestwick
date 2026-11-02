# Prestwick

Design a golf course, then play it. Godot 4.7, GDScript, isometric 2D.

- `CLAUDE.md` is the contract for working in this repo with Claude Code.
- `docs/design.md` holds the numbers and rules; the full design doc is in Claude Docs.
- `docs/BACKLOG.md` is the plan. Start with `/next-story`.
- `bash scripts/run_tests.sh` runs parse, scene and GUT checks headless.
- `bash scripts/playtest.sh` runs the headless smoke; `docs/export.md` covers builds.

## Setup

1. Install Godot 4.7 (or `bash scripts/install_godot.sh` for a local headless binary).
2. GUT 9.7.1 ships in `addons/gut`. To upgrade, replace that folder with a release whose table in the GUT README lists your Godot version.
3. `claude` in this folder, then `/next-story`.
