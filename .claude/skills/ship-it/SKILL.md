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
2. Run `/playtest` in smoke mode (one hole, one guest, one day). Must pass.
3. Bump the version in `project.godot` (`config/version`): milestone number as minor, so E2 done = `0.2.0`.
4. Export with the headless editor:
   ```
   godot --headless --export-release "Linux" build/prestwick-<version>-linux.x86_64
   godot --headless --export-release "Windows" build/prestwick-<version>-win.exe
   ```
   Export presets live in `export_presets.cfg`. If a preset is missing, create it with the defaults in `docs/export.md` and note it.
5. Write `docs/releases/<version>.md`: three to eight lines. What a player can now do, what is known broken, what the next milestone adds. No internal story ids.
6. Copy the newest example course into `build/courses/` so the build ships with something to play.
7. Commit `release: <version>` and tag `v<version>`.
8. Do not push. Say the tag, the build paths and the release note path in three lines.

## Rules

- Never ship with a failing test, a script error, or a red playtest.
- Never edit the backlog here. Shipping does not close stories; `/next-story` does.
- If `godot` is not on PATH, say so and stop; do not install anything.
