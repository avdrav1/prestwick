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

## validate

Runs `course/validator.gd` headless on the file and prints each rule as pass or fail with the offending tile. Same rules as the in-game validator; never a separate implementation.

## generate

Writes `courses/gen_par<par>_<terrain>_<water>.json`: a tee box, a fairway corridor of the right yardage, rough either side, a green with the cup, optional water on the direct line, hills as a gentle ridge. It must pass `validate`. Used for test fixtures and smoke playtests.

## inspect

Prints yardage per hole, surface counts, height range, and build cost at the rates in `docs/design.md`.

## Rules

- Bump `version` only through `/decision`; add a migration in `course/save.gd` in the same story.
- Never hand-edit the `tiles` field; regenerate.
