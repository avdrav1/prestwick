---
name: course-file
description: Validate, generate, or inspect a Prestwick course JSON file in courses/. Use when a test needs a fixture course, the user shares a course file, or asks "make me a par 5".
---

# Course file

Argument: `validate <path>`, `generate <par> [flat|hilly] [water|dry]`, or `inspect <path>`.

## Format (version 2)

```json
{
  "version": 2,
  "name": "Example Par 3",
  "author": "",
  "width": 40,
  "height": 40,
  "tiles": "<base64 of width*height bytes, each (height << 4) | surface>",
  "holes": [
    {"number": 1, "par": 3, "tee": [4, 20], "cup": [34, 20], "open": true}
  ],
  "thumbnail": "",
  "owned": ["111", "111", "111"],
  "land_budget": null
}
```

Surface enum: 0 fairway, 1 rough, 2 green, 3 tee, 4 bunker, 5 water, 6 trees, 7 cart_path, 8 oob. Height 0 to 7 in the high nibble.

Land (version 2, E6-S3, D26): `owned` has one string per parcel row (16 x 16 tiles, `CourseData.PARCEL_TILES`), top row first, one character per parcel, `"1"` owned and `"0"` not, so a 40 x 40 map has 3 rows of 3 (the last parcels partial). `land_budget` is the whole dollars left to buy parcels with, or `null` for no limit (New sandbox). Version 1 files (no `owned`, no `land_budget`) still load: `course/save.gd` migrates them with every parcel owned and `land_budget` null, and saves them as version 2. `generate` writes every parcel owned and `null`.

## Headless entry point

`validate`, `generate` and `inspect` run through `course/course_file.gd` (E2-S2, E2-S18):

```
godot --headless --path . -s res://course/course_file.gd -- validate courses/example_par3.json
godot --headless --path . -s res://course/course_file.gd -- generate 3 flat dry --out=courses/example_par3.json
godot --headless --path . -s res://course/course_file.gd -- generate 4 hilly dry
godot --headless --path . -s res://course/course_file.gd -- inspect courses/example_par3.json
```

Exit code 0 when every rule passes, 1 when a rule fails, 2 for bad arguments or a file that does not load. `inspect` only reports: it exits 0 whenever the file loads, failing rules included.

## validate

Runs `course/validator.gd` headless on the file and prints each rule as pass or fail with the offending tile. Same rules as the in-game validator; never a separate implementation.

## generate

Writes `courses/gen_par<par>_<terrain>_<water>.json` (or `--out=<path>`): a tee box, a fairway corridor of the right yardage, rough either side, a green with the cup, optional water on the direct line, and with `hilly` the same hole laid over `LandGenerator` heights (seed `CourseGenerator.HILLY_LAND_SEED`, the window centred on the land map) with the tee box, green and pond levelled flat and edge neighbours one step apart at most (E2-S18, E6-S20, D19). It must pass `validate`, and the tool validates what it wrote. Used for test fixtures and smoke playtests. `courses/example_par3.json` is `generate 3 flat dry`.

## inspect

Prints the size in tiles and yards, the height range, the tile count of each surface present, the land (`land: <w>x<h> parcels of 16 tiles, <n> owned`, then the owned grid one parcel row per line as in `owned`, then `land budget: $4,200` or `land budget: unlimited`), and one line per hole: par, yardage, open or closed, and the validator's PASS or FAIL, then a line for each failing rule with its tile and reason. Build cost at the rates in `docs/design.md` is not printed yet: tile costs get a resource in E4.

## Rules

- Bump `version` only through `/decision`; add a migration in `course/save.gd` in the same story.
- Never hand-edit the `tiles` field; regenerate.
