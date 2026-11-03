---
name: course-file
description: Validate, generate, or inspect a Prestwick course JSON file in courses/. Use when a test needs a fixture course, the user shares a course file, or asks "make me a par 5".
---

# Course file

Argument: `validate <path>`, `generate <par> [flat|hilly] [water|dry]`, or `inspect <path>`.

## Format (version 1)

```json
{
  "version": 1,
  "name": "Example Par 3",
  "author": "",
  "width": 40,
  "height": 40,
  "tiles": "<base64 of width*height bytes, each (height << 4) | surface>",
  "holes": [
    {"number": 1, "par": 3, "tee": [4, 20], "cup": [34, 20], "open": true}
  ],
  "thumbnail": ""
}
```

Surface enum: 0 fairway, 1 rough, 2 green, 3 tee, 4 bunker, 5 water, 6 trees, 7 cart_path, 8 oob. Height 0 to 7 in the high nibble.

## Headless entry point

`validate` and `generate` run through `course/course_file.gd` (E2-S2):

```
godot --headless --path . -s res://course/course_file.gd -- validate courses/example_par3.json
godot --headless --path . -s res://course/course_file.gd -- generate 3 flat dry --out=courses/example_par3.json
```

Exit code 0 when every rule passes, 1 when a rule fails, 2 for bad arguments or a file that does not load.

## validate

Runs `course/validator.gd` headless on the file and prints each rule as pass or fail with the offending tile. Same rules as the in-game validator; never a separate implementation.

## generate

Writes `courses/gen_par<par>_<terrain>_<water>.json` (or `--out=<path>`): a tee box, a fairway corridor of the right yardage, rough either side, a green with the cup, optional water on the direct line, hills as a gentle ridge (`hilly` is not built yet). It must pass `validate`, and the tool validates what it wrote. Used for test fixtures and smoke playtests. `courses/example_par3.json` is `generate 3 flat dry`.

## inspect

Prints yardage per hole, surface counts, height range, and build cost at the rates in `docs/design.md`.

## Rules

- Bump `version` only through `/decision`; add a migration in `course/save.gd` in the same story.
- Never hand-edit the `tiles` field; regenerate.
