---
name: ship-it
description: Cut a milestone build of Prestwick. Verifies the epic is complete, runs all checks, exports Linux and Windows builds, writes release notes, tags the commit. Use when the user says "ship it" or an epic is done.
---

# Ship it

## Preconditions

- The active epic has every story checked. If not, list the unchecked ones and stop.
- Working tree is clean. If not, show `git status` and stop.

## Steps

1. Run `/godot-check`. Must pass.
2. Run `/playtest` in smoke mode (`bash scripts/playtest.sh`). It checks every stage built so far (see the playtest skill). Must pass. Then its windowed step: `godot --path . -s res://scripts/shirt_render_check.gd` (needs a display; E3-S32). Must pass; with no display, say it was skipped in the release note's known issues.
3. Bump the version in `project.godot` (`config/version`): milestone number as minor, so E2 done = `0.2.0`.
4. Export with the headless editor:
   ```
   mkdir -p build
   godot --headless --path . --export-release "Linux" build/prestwick-<version>-linux.x86_64
   godot --headless --path . --export-release "Windows" build/prestwick-<version>-win.exe
   bash scripts/check_build.sh build/prestwick-<version>-linux.x86_64
   ```
   Export presets live in `export_presets.cfg`. If a preset is missing, create it with the defaults in `docs/export.md` and note it. Export templates for 4.7.2 must be installed (`docs/export.md`); if they are not, say so and stop. `check_build.sh` must pass.
5. Write `docs/releases/<version>.md`: three to eight lines. What a player can now do, what is known broken, what the next milestone adds. No internal story ids.
6. Copy the example courses into `build/courses/` so the build ships with something to play: `courses/harbor_links.json`, `courses/old_grey_links.json`, `courses/pine_ridge.json`, `courses/cliffside.json` (E13), `courses/dogleg_hollow.json` (E16), `courses/old_grey_championship.json` (E18), `courses/dogleg_hollow_championship.json` (E19) and `courses/playtest_nine.json`. The exported pack carries the seven too (`include_filter` `courses/*.json`), and the game plays them from there on its Famous courses page (D70, `FamousCourses`; it no longer copies them into the player's course folder).
7. Commit `release: <version>` and tag `v<version>`.
8. Push only when the user asks (`git push origin main --tags`). Say the tag, the build paths and the release note path in three lines.
9. When the user asks to publish to itch.io (avdrav.itch.io/prestwick, butler in `~/.local/bin`, logged in): stage `build/itch-<version>/linux/prestwick.x86_64` and `build/itch-<version>/windows/Prestwick.exe` (the same file names every release, so the itch app updates in place), each folder with `how-to-play.md` and a `courses/` folder holding the same six files as step 6 (`courses/harbor_links.json`, `courses/old_grey_links.json`, `courses/pine_ridge.json`, `courses/cliffside.json`, `courses/dogleg_hollow.json` and `courses/playtest_nine.json`); then `butler push build/itch-<version>/linux avdrav/prestwick:linux --userversion <version>` and the same for `windows`, and wait for `butler status avdrav/prestwick:<channel>` to show the build done. Never use `rm -rf` (denied); stage into a new folder per version.

## Rules

- Never ship with a failing test, a script error, or a red playtest.
- Never edit the backlog here. Shipping does not close stories; `/next-story` does.
- If `godot` is not on PATH, say so and stop; do not install anything.
