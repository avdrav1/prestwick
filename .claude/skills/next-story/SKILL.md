---
name: next-story
description: Take the first unchecked story of the active epic in docs/BACKLOG.md, implement it with tests, verify with /godot-check, and check it off. Use when the user says "next story", "next", or "keep going".
---

# Next story

## Steps

1. Read `docs/BACKLOG.md`. Take the first unchecked story in the `active` epic. Say its id and title in one line.
2. Read `CLAUDE.md` and the relevant section of `docs/design.md`. Read every file in the folders the story touches.
3. Plan in 3 to 6 lines: files to add or change, the test, anything the story leaves for later. Proceed without asking unless two valid designs exist with different costs.
4. Write the test first when the story has a named test file. Use GUT (`extends GutTest`).
5. Implement. Follow the architecture rules in `CLAUDE.md`: only `builder.gd` and `save.gd` write CourseData; ball physics is custom; tunables live in `.tres` or `data/*.json`.
6. Run `/godot-check`. Fix until it passes. Never check off a story with a failing test or a script error.
7. If the story is visual (renderer, HUD, sprites), take a screenshot with the headless runner (`scripts/screenshot.sh <scene>`) and look at it before calling it done.
8. Check the story off in `docs/BACKLOG.md`. If the work exposed a missing story, add it to the end of the epic with a note.
9. Commit: `story: E<n>-S<m> <title>`.
10. Report in 3 lines: what changed, what the test asserts, what the next story is.

## Rules

- One story per invocation. Do not start the next one.
- If the story contradicts `docs/design.md`, stop and ask; do not pick a side silently.
- If the acceptance criterion cannot be verified with the tools available, say so and propose a narrower one.
- New tunable numbers go in a resource and get a line in `docs/design.md`.
