# Prestwick

Isometric golf game: design a course, then play it. Inspired by Sid Meier's SimGolf (build and manage) and Mean 18 (overhead golf, course architect). Godot 4.3+, GDScript, 2D renderer.

The full design doc lives in Claude Docs (Prestwick, Game Design Doc). `docs/design.md` carries the parts that matter for code. When they disagree, `docs/design.md` wins for implementation and the design doc wins for intent; fix the loser.

## Pillars (settle scope arguments in this order)

1. Every hole is playable the moment you place it.
2. Shots are readable.
3. The course tells a story through its guests.
4. Small, finishable scope.

## Workflow

Work is tracked in `docs/BACKLOG.md` as epics and stories. Use the skills:

- `/next-epic` picks the next epic and writes its stories.
- `/next-story` picks the next story, implements it, tests it, and checks it off.
- `/ship-it` cuts a milestone build and tags it.
- `/playtest` runs a scripted playtest and records findings.
- `/godot-check` runs the headless Godot checks and GUT tests.
- `/balance` tunes a numeric table (clubs, surfaces, reactions, economy) against the design targets.
- `/art-spec` writes the spec for a sprite or tile set before any art is drawn.
- `/course-file` validates, generates or inspects a course JSON file.
- `/decision` records an architecture or design decision in `docs/DECISIONS.md`.

One story per commit. Commit message: `story: <id> <title>`.

## Architecture (do not drift from this)

- `course/CourseData` is the single source of truth: a `Resource` with a 2D tile array (height 0 to 7, surface enum) and a list of holes (tee, cup, par, number, open).
- Only `course/builder.gd` and `course/save.gd` write to CourseData. Everything else reads.
- `golf/ball.gd` is custom physics: a 3D position stepped at 60 Hz over the height map. Never use Godot's physics bodies for the ball.
- `guests/` simulates on a timer, once per simulated second, not per frame.
- Build and Play are states on one main scene, never separate scenes.
- Grid: 5 yards per tile. Isometric 2:1, 64x32 tile footprint, 16 px per height step.

## Folders

```
scenes/   main, hud, menus
course/   data, builder, validator, tile rules, save/export
golf/     swing, ball, clubs, lies
guests/   spawner, brain, reactions, rating
art/      tiles, sprites, ui
audio/
courses/  example course JSON files
tests/    GUT tests
scripts/  run_tests.sh, headless checks
docs/     design.md, BACKLOG.md, DECISIONS.md, playtests/
```

## Rules

- GDScript with static typing. `class_name` on every reusable script.
- No `get_node` string paths outside `_ready`. Use `@onready` and exported node paths.
- Every validator rule, ball step and reaction check has a GUT test before the story closes.
- Numbers that designers tune live in `*.tres` resources or `data/*.json`, never as literals in logic.
- Do not add features that are in the "Out of the MVP" list in `docs/design.md` without a `/decision`.
- Run `/godot-check` before saying a story is done.
