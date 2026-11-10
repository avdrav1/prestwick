---
name: course-file
description: Validate, generate, or inspect a Prestwick course JSON file in courses/. Use when a test needs a fixture course, the user shares a course file, or asks "make me a par 5".
---

# Course file

Argument: `validate <path>`, `generate <par> [flat|hilly] [water|dry]`, or `inspect <path>`.

## Format (version 3)

```json
{
  "version": 3,
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
  "land_budget": null,
  "clubhouse": {"x": 20, "y": 33, "facing": "+y"}
}
```

Surface enum: 0 fairway, 1 rough, 2 green, 3 tee, 4 bunker, 5 water, 6 trees, 7 cart_path, 8 oob. Height 0 to 7 in the high nibble.

Holes (E3-S2): at most `max_holes` (9, `course/builder_tuning.tres`), each numbered 1 to 9. A file with more holes, or a number outside 1 to 9, does not load (`validate` exits 2 and says why). Two holes sharing a number load and fail rule 1.

Land (version 2, E6-S3, D26): `owned` has one string per parcel row (16 x 16 tiles, `CourseData.PARCEL_TILES`), top row first, one character per parcel, `"1"` owned and `"0"` not, so a 40 x 40 map has 3 rows of 3 (the last parcels partial). `land_budget` is the balance (E4-S2, D57: the one balance that building and parcels both come out of) in whole dollars, below 0 when upkeep took it there, or `null` for no limit (New sandbox). Version 1 files (no `owned`, no `land_budget`) still load: `course/save.gd` migrates them with every parcel owned and `land_budget` null, and saves them as version 2. `generate` writes every parcel owned and `null`.

Clubhouse (version 3, E5-S9, D60): `clubhouse` is the 3x3 clubhouse's centre tile and its facing, the side its door is on (`"+x"`, `"+y"`, `"-x"` or `"-y"`; the door is the tile just outside the middle of that side), or `null` for none (then no guests come). Its footprint and door must be on the map. Version 1 and 2 files load with one placed by rule (`course/clubhouse_rule.gd`: in the starting block at the middle of its +y edge, else beside hole 1's tee, else none) and save as version 3. `generate` places one by the same rule. `inspect` prints it.

## Headless entry point

`validate`, `generate` and `inspect` run through `course/course_file.gd` (E2-S2, E2-S18):

```
godot --headless --path . -s res://course/course_file.gd -- validate courses/example_par3.json
godot --headless --path . -s res://course/course_file.gd -- generate 3 flat dry --out=courses/example_par3.json
godot --headless --path . -s res://course/course_file.gd -- generate 4 hilly dry
godot --headless --path . -s res://course/course_file.gd -- inspect courses/example_par3.json
```

Exit code 0 when every rule passes, 1 when a rule fails, 2 for bad arguments or a file that does not load. `inspect` only reports: it exits 0 whenever the file loads, failing rules included. A hole under `zone_from_yd` (300 yd) has no landing zone, and `inspect` does not say so: a par 4 that short already fails rule 4, and that issue is the one to fix (E6-S39).

## validate

Runs `course/validator.gd` headless on the file and prints each rule as pass or fail with the offending tile. Same rules as the in-game validator; never a separate implementation.

## generate

Writes `courses/gen_par<par>_<terrain>_<water>.json` (or `--out=<path>`): a tee box, a fairway corridor of the right yardage, rough either side, a green with the cup, optional water on the direct line, and with `hilly` the same hole laid over `LandGenerator` heights (seed `CourseGenerator.HILLY_LAND_SEED`, the window centred on the land map) with the land's ponds filled back to their shore, the tee box, green and pond levelled flat on the land's 2 x 2 terrace cells, and the land's slope rule kept: edge neighbours one step apart at most and at most one riser every 2 tiles along either axis, so its balls settle inside D16 (E2-S18, E6-S20, E6-S29, D19; `tests/test_settle.gd`). Hilly output follows `course/land_tuning.tres`: retuning land changes every generated hilly course, so regenerate any saved `gen_par*_hilly_*.json` after a land retune (none is checked in) and rerun `tests/test_course_file.gd` and `tests/test_settle.gd` (its default worst strikes come from `scripts/run_tests.sh --full`). It must pass `validate`, and the tool validates what it wrote. Used for test fixtures and smoke playtests. `courses/example_par3.json` is `generate 3 flat dry`.

## inspect

Prints the size in tiles and yards, the height range, the tile count of each surface present, the land (`land: <w>x<h> parcels of 16 tiles, <n> owned`, then the owned grid one parcel row per line as in `owned`, then `land budget: $4,200` or `land budget: unlimited`), and one line per hole: par, yardage, open or closed, and the validator's PASS or FAIL, then a line for each failing rule with its tile and reason. After the surfaces, the build cost (E4-S2): `build cost: $957 to paint every tile not rough (heights not counted)` at `data/economy.json`'s `tile_price` (D56), then one line per painted surface, `  green: 45 x $15 = $675`. The file does not say what land it was built on, so every tile not rough counts as painted (a generated land's own trees and water too) and height moved is left out.

## Rules

- Bump `version` only through `/decision`; add a migration in `course/save.gd` in the same story.
- Never hand-edit the `tiles` field; regenerate.
